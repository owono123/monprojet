package com.monprojet.ia.data

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Historique des conversations, en fichiers JSON dans le stockage prive de l'application.
 * Rien ne sort de l'appareil et rien n'est sauvegarde ailleurs.
 */
class ConversationStore(context: Context) {

    private val dir = File(context.filesDir, "conversations").apply { mkdirs() }

    /** Liste des conversations, la plus recemment modifiee en premier. */
    fun list(): JSONArray {
        val items = dir.listFiles { f -> f.isFile && f.name.endsWith(".json") }
            ?.sortedByDescending { it.lastModified() }
            ?: emptyList()

        val array = JSONArray()
        for (file in items) {
            val json = runCatching { JSONObject(file.readText()) }.getOrNull() ?: continue
            array.put(
                JSONObject()
                    .put("id", file.nameWithoutExtension)
                    .put("title", json.optString("title", "Sans titre"))
                    .put("updatedAt", file.lastModified())
            )
        }
        return array
    }

    fun load(id: String): JSONObject? {
        val file = fileFor(id) ?: return null
        if (!file.isFile) return null
        return runCatching { JSONObject(file.readText()) }.getOrNull()
    }

    fun save(id: String, title: String, messages: JSONArray) {
        val file = fileFor(id) ?: return
        val json = JSONObject()
            .put("title", title.take(TITLE_LIMIT))
            .put("messages", messages)
        file.writeText(json.toString())
    }

    fun delete(id: String): Boolean = fileFor(id)?.delete() ?: false

    /**
     * L'identifiant vient de la page : il ne doit designer qu'un fichier de ce repertoire,
     * jamais un chemin ailleurs sur le disque.
     */
    private fun fileFor(id: String): File? {
        if (id.isEmpty() || !id.all { it.isLetterOrDigit() || it == '-' || it == '_' }) return null
        return File(dir, "$id.json")
    }

    private companion object {
        const val TITLE_LIMIT = 80
    }
}
