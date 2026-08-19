package com.monprojet.ia.model

import android.app.ActivityManager
import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Un modele telechargeable au format .task de MediaPipe.
 *
 * [promptTemplate] applique le format de dialogue attendu par le modele ; sans lui, un
 * modele instruit repond souvent a cote. Les marqueurs {system} et {user} y sont remplaces.
 */
data class ModelSpec(
    val id: String,
    val label: String,
    val url: String,
    val approxBytes: Long,
    val minRamMb: Int,
    val gated: Boolean,
    val promptTemplate: String,
    val note: String,
)

object ModelCatalog {

    private const val CHATML = "<|im_start|>system\n{system}<|im_end|>\n" +
        "<|im_start|>user\n{user}<|im_end|>\n<|im_start|>assistant\n"

    private const val GEMMA = "<start_of_turn>user\n{system}\n\n{user}<end_of_turn>\n" +
        "<start_of_turn>model\n"

    val ALL: List<ModelSpec> = listOf(
        ModelSpec(
            id = "qwen2.5-0.5b",
            label = "Qwen2.5 0.5B Instruct",
            url = "https://huggingface.co/litert-community/Qwen2.5-0.5B-Instruct/resolve/main/Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task",
            approxBytes = 550L * 1024 * 1024,
            minRamMb = 2048,
            gated = false,
            promptTemplate = CHATML,
            note = "Le plus leger. A privilegier en dessous de 4 Go de RAM.",
        ),
        ModelSpec(
            id = "qwen2.5-1.5b",
            label = "Qwen2.5 1.5B Instruct",
            url = "https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv1280.task",
            approxBytes = 1700L * 1024 * 1024,
            minRamMb = 4096,
            gated = false,
            promptTemplate = CHATML,
            note = "Nettement meilleur en code et en raisonnement, mais plus lent.",
        ),
        ModelSpec(
            id = "gemma3-1b",
            label = "Gemma 3 1B Instruct",
            url = "https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task",
            approxBytes = 560L * 1024 * 1024,
            minRamMb = 3072,
            gated = true,
            promptTemplate = GEMMA,
            note = "Necessite un jeton Hugging Face et l'acceptation de la licence Gemma.",
        ),
    )

    /** Identifiant reserve au fichier .task importe depuis le stockage du telephone. */
    const val IMPORTED_ID = "importe"

    val IMPORTED = ModelSpec(
        id = IMPORTED_ID,
        label = "Modele importe",
        url = "",
        approxBytes = 0,
        minRamMb = 0,
        gated = false,
        // Le format de dialogue d'un fichier apporte par l'utilisateur est inconnu :
        // il se regle a la main dans les reglages.
        promptTemplate = CHATML,
        note = "Fichier .task fourni par toi. Verifie le format de dialogue dans les reglages.",
    )

    fun byId(id: String): ModelSpec? =
        if (id == IMPORTED_ID) IMPORTED else ALL.firstOrNull { it.id == id }

    /** Memoire vive totale de l'appareil, en mebioctets. */
    fun totalRamMb(context: Context): Int {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val info = ActivityManager.MemoryInfo()
        am.getMemoryInfo(info)
        return (info.totalMem / (1024 * 1024)).toInt()
    }

    /**
     * Modele conseille pour cet appareil : le plus capable dont les besoins tiennent dans
     * la RAM, en excluant les modeles a licence pour que le premier lancement aboutisse
     * sans compte Hugging Face.
     */
    fun recommendedFor(context: Context): ModelSpec {
        val ram = totalRamMb(context)
        return ALL.filter { !it.gated && it.minRamMb <= ram }.maxByOrNull { it.minRamMb }
            ?: ALL.first()
    }

    fun toJson(context: Context): JSONArray {
        val ram = totalRamMb(context)
        val array = JSONArray()
        for (m in ALL) {
            array.put(
                JSONObject()
                    .put("id", m.id)
                    .put("label", m.label)
                    .put("approxBytes", m.approxBytes)
                    .put("minRamMb", m.minRamMb)
                    .put("gated", m.gated)
                    .put("note", m.note)
                    .put("fitsInRam", m.minRamMb <= ram)
            )
        }
        return array
    }
}
