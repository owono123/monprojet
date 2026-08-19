package com.monprojet.ia.model

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * Telechargement du fichier de modele, avec reprise. Un fichier de plusieurs centaines de
 * megaoctets sur une connexion mobile ne passe pas toujours du premier coup : le
 * telechargement se poursuit dans un fichier .part et reprend a l'octet ou il s'etait
 * arrete, via un en-tete Range.
 */
class ModelDownloader(private val store: ModelStore) {

    data class Progress(val downloadedBytes: Long, val totalBytes: Long)

    /**
     * @param token jeton Hugging Face, requis seulement pour les modeles a licence.
     * @throws IllegalStateException si le serveur refuse la requete, avec un message
     *   exploitable dans l'interface.
     */
    suspend fun download(
        spec: ModelSpec,
        token: String,
        onProgress: (Progress) -> Unit,
    ): File = withContext(Dispatchers.IO) {
        val target = store.fileFor(spec.id)
        val part = File(target.parentFile, "${target.name}.part")
        val already = if (part.isFile) part.length() else 0L

        val connection = (URL(spec.url).openConnection() as HttpURLConnection).apply {
            instanceFollowRedirects = true
            connectTimeout = 30_000
            readTimeout = 60_000
            if (token.isNotBlank()) setRequestProperty("Authorization", "Bearer $token")
            if (already > 0) setRequestProperty("Range", "bytes=$already-")
        }

        try {
            connection.connect()
            val code = connection.responseCode
            val resuming = code == HttpURLConnection.HTTP_PARTIAL

            if (code !in 200..299) {
                throw IllegalStateException(explain(code, spec))
            }

            // Le serveur peut ignorer la demande de reprise : dans ce cas on repart de zero.
            val startAt = if (resuming) already else 0L
            val remaining = connection.contentLengthLong.takeIf { it > 0 } ?: -1L
            val total = if (remaining > 0) startAt + remaining else spec.approxBytes

            FileOutputStream(part, resuming).use { output ->
                connection.inputStream.use { input ->
                    val buffer = ByteArray(1 shl 16)
                    var written = startAt
                    var lastNotified = 0L
                    while (true) {
                        currentCoroutineContext().ensureActive()
                        val read = input.read(buffer)
                        if (read <= 0) break
                        output.write(buffer, 0, read)
                        written += read
                        // Une notification tous les 2 Mo : inutile de reveiller l'interface
                        // a chaque bloc de 64 Ko.
                        if (written - lastNotified >= 2L * 1024 * 1024) {
                            lastNotified = written
                            onProgress(Progress(written, total))
                        }
                    }
                    onProgress(Progress(written, total))
                }
            }
        } finally {
            connection.disconnect()
        }

        if (target.exists()) target.delete()
        check(part.renameTo(target)) { "Impossible de finaliser le telechargement" }
        target
    }

    private fun explain(code: Int, spec: ModelSpec): String = when {
        code == 401 || code == 403 ->
            if (spec.gated) {
                "Acces refuse ($code). Ce modele demande d'accepter sa licence sur Hugging " +
                    "Face et de renseigner un jeton d'acces dans les reglages."
            } else {
                "Acces refuse ($code) par le serveur du modele."
            }
        code == 404 ->
            "Fichier introuvable (404). L'adresse du modele a probablement change ; elle " +
                "peut etre corrigee dans le depot, ou le fichier importe manuellement."
        else -> "Le serveur a repondu $code."
    }

    /** Supprime un telechargement interrompu pour repartir proprement. */
    fun discardPartial(spec: ModelSpec) {
        val target = store.fileFor(spec.id)
        File(target.parentFile, "${target.name}.part").delete()
    }
}
