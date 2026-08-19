package com.monprojet.ia.export

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/**
 * Reconstruit un projet a partir d'une reponse du modele et l'emballe en archive ZIP.
 *
 * Le profil « developpeur » demande au modele d'annoter chaque bloc de code du chemin du
 * fichier :
 *
 *     ```kotlin path=app/src/main/java/Exemple.kt
 *
 * Compiler un APK sur le telephone lui-meme n'est pas possible — il n'existe pas de chaine
 * de compilation Android executable sous Android 9. L'archive est donc destinee a etre
 * poussee sur un depot, ou une integration continue produit l'APK.
 */
class ProjectExporter(private val context: Context) {

    data class FileEntry(val path: String, val content: String)

    fun parse(markdown: String): List<FileEntry> =
        BLOCK.findAll(markdown)
            .mapNotNull { match ->
                val path = sanitize(match.groupValues[2]) ?: return@mapNotNull null
                FileEntry(path, match.groupValues[3])
            }
            .distinctBy { it.path }
            .toList()

    /**
     * Rejette les chemins absolus et les remontees de repertoire : le contenu vient du
     * modele, il n'a pas a decider d'ecrire hors de l'archive.
     */
    private fun sanitize(raw: String): String? {
        val path = raw.trim().trim('"', '\'').removePrefix("./")
        if (path.isEmpty() || path.startsWith("/") || path.contains("..")) return null
        if (path.contains('\\')) return null
        return path
    }

    fun writeZip(entries: List<FileEntry>, baseName: String): File {
        require(entries.isNotEmpty()) { "Aucun fichier a exporter" }

        val dir = File(context.cacheDir, "exports").apply { mkdirs() }
        val zip = File(dir, "$baseName.zip")

        ZipOutputStream(zip.outputStream().buffered()).use { out ->
            for (entry in entries) {
                out.putNextEntry(ZipEntry(entry.path))
                out.write(entry.content.toByteArray())
                out.closeEntry()
            }
        }
        return zip
    }

    fun shareIntent(zip: File): Intent {
        val uri: Uri = FileProvider.getUriForFile(context, "${context.packageName}.files", zip)
        return Intent(Intent.ACTION_SEND).apply {
            type = "application/zip"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
    }

    private companion object {
        // Bloc de code dont la ligne d'ouverture porte « path=<chemin> ».
        val BLOCK = Regex(
            """```([A-Za-z0-9+#._-]*)[ \t]+path=([^\s`]+)[ \t]*\r?\n(.*?)```""",
            RegexOption.DOT_MATCHES_ALL,
        )
    }
}
