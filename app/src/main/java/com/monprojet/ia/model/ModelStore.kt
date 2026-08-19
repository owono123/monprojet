package com.monprojet.ia.model

import android.content.Context
import android.net.Uri
import java.io.File

/**
 * Emplacement des fichiers de modele. Ils vivent dans le repertoire prive de
 * l'application : aucune autre application ne peut les lire, et ils sont supprimes avec
 * elle.
 */
class ModelStore(private val context: Context) {

    private val dir: File
        get() = File(context.filesDir, "models").apply { mkdirs() }

    fun fileFor(modelId: String): File = File(dir, "$modelId.task")

    fun isInstalled(modelId: String): Boolean {
        val f = fileFor(modelId)
        return f.isFile && f.length() > 0
    }

    fun installedIds(): List<String> =
        dir.listFiles { f -> f.isFile && f.name.endsWith(".task") }
            ?.map { it.name.removeSuffix(".task") }
            ?: emptyList()

    fun delete(modelId: String): Boolean = fileFor(modelId).delete()

    fun freeSpaceBytes(): Long = dir.usableSpace

    /**
     * Copie un fichier .task choisi par l'utilisateur dans le stockage de l'application.
     * Utile quand le telechargement direct echoue ou que le fichier a ete recupere sur un
     * ordinateur.
     */
    fun importFrom(uri: Uri, modelId: String, onProgress: (Long) -> Unit): File {
        val target = fileFor(modelId)
        val tmp = File(target.parentFile, "${target.name}.part")
        context.contentResolver.openInputStream(uri).use { input ->
            requireNotNull(input) { "Fichier illisible" }
            tmp.outputStream().use { output ->
                val buffer = ByteArray(1 shl 16)
                var copied = 0L
                while (true) {
                    val read = input.read(buffer)
                    if (read <= 0) break
                    output.write(buffer, 0, read)
                    copied += read
                    onProgress(copied)
                }
            }
        }
        if (target.exists()) target.delete()
        check(tmp.renameTo(target)) { "Impossible de finaliser l'import" }
        return target
    }
}
