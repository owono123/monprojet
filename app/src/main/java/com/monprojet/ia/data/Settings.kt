package com.monprojet.ia.data

import android.content.Context
import androidx.core.content.edit
import org.json.JSONObject

/**
 * Reglages persistants. SharedPreferences suffit ici : quelques dizaines de valeurs,
 * lues au demarrage et ecrites a chaque modification depuis l'interface.
 */
class Settings(context: Context) {

    private val prefs = context.getSharedPreferences("ia_locale", Context.MODE_PRIVATE)

    var personaId: String
        get() = prefs.getString(KEY_PERSONA, Personas.DEFAULT_ID)!!
        set(v) = prefs.edit { putString(KEY_PERSONA, v) }

    /** Prompt systeme personnalise ; vide signifie « utiliser celui du profil ». */
    var customSystemPrompt: String
        get() = prefs.getString(KEY_CUSTOM_PROMPT, "")!!
        set(v) = prefs.edit { putString(KEY_CUSTOM_PROMPT, v) }

    var modelId: String
        get() = prefs.getString(KEY_MODEL_ID, "")!!
        set(v) = prefs.edit { putString(KEY_MODEL_ID, v) }

    var temperature: Float
        get() = prefs.getFloat(KEY_TEMPERATURE, 0.7f)
        set(v) = prefs.edit { putFloat(KEY_TEMPERATURE, v) }

    var topK: Int
        get() = prefs.getInt(KEY_TOP_K, 40)
        set(v) = prefs.edit { putInt(KEY_TOP_K, v) }

    var topP: Float
        get() = prefs.getFloat(KEY_TOP_P, 0.95f)
        set(v) = prefs.edit { putFloat(KEY_TOP_P, v) }

    var maxTokens: Int
        get() = prefs.getInt(KEY_MAX_TOKENS, 1024)
        set(v) = prefs.edit { putInt(KEY_MAX_TOKENS, v) }

    /** Nombre de passes de critique du mode reflexion : 0 desactive le mode. */
    var deliberationPasses: Int
        get() = prefs.getInt(KEY_PASSES, 0)
        set(v) = prefs.edit { putInt(KEY_PASSES, v.coerceIn(0, 3)) }

    /** La recherche web est la seule fonction qui sort de l'appareil. Eteinte par defaut. */
    var webSearchEnabled: Boolean
        get() = prefs.getBoolean(KEY_SEARCH, false)
        set(v) = prefs.edit { putBoolean(KEY_SEARCH, v) }

    /** Instance SearXNG personnelle ; vide signifie « utiliser DuckDuckGo Lite ». */
    var searxUrl: String
        get() = prefs.getString(KEY_SEARX, "")!!
        set(v) = prefs.edit { putString(KEY_SEARX, v) }

    /** Jeton Hugging Face, requis seulement pour les modeles a licence acceptee (Gemma). */
    var huggingFaceToken: String
        get() = prefs.getString(KEY_HF_TOKEN, "")!!
        set(v) = prefs.edit { putString(KEY_HF_TOKEN, v) }

    /**
     * Format de dialogue impose : "" laisse celui du modele, sinon "chatml", "gemma" ou
     * "aucun". Sert surtout pour un fichier importe, dont le format n'est pas connu.
     */
    var promptTemplate: String
        get() = prefs.getString(KEY_TEMPLATE, "")!!
        set(v) = prefs.edit { putString(KEY_TEMPLATE, v) }

    /** "CPU" ou "GPU". Le CPU est le choix sur pour un appareil ancien. */
    var backend: String
        get() = prefs.getString(KEY_BACKEND, "CPU")!!
        set(v) = prefs.edit { putString(KEY_BACKEND, v) }

    /** Prompt systeme effectivement envoye au modele. */
    fun effectiveSystemPrompt(): String {
        val custom = customSystemPrompt
        return if (custom.isNotBlank()) custom else Personas.byId(personaId).systemPrompt
    }

    fun toJson(): JSONObject = JSONObject()
        .put("personaId", personaId)
        .put("customSystemPrompt", customSystemPrompt)
        .put("modelId", modelId)
        .put("temperature", temperature.toDouble())
        .put("topK", topK)
        .put("topP", topP.toDouble())
        .put("maxTokens", maxTokens)
        .put("deliberationPasses", deliberationPasses)
        .put("webSearchEnabled", webSearchEnabled)
        .put("searxUrl", searxUrl)
        .put("huggingFaceToken", huggingFaceToken)
        .put("backend", backend)
        .put("promptTemplate", promptTemplate)

    /** Applique les cles presentes dans [json] ; les absentes restent inchangees. */
    fun apply(json: JSONObject) {
        if (json.has("personaId")) personaId = json.getString("personaId")
        if (json.has("customSystemPrompt")) customSystemPrompt = json.getString("customSystemPrompt")
        if (json.has("temperature")) temperature = json.getDouble("temperature").toFloat()
        if (json.has("topK")) topK = json.getInt("topK")
        if (json.has("topP")) topP = json.getDouble("topP").toFloat()
        if (json.has("maxTokens")) maxTokens = json.getInt("maxTokens")
        if (json.has("deliberationPasses")) deliberationPasses = json.getInt("deliberationPasses")
        if (json.has("webSearchEnabled")) webSearchEnabled = json.getBoolean("webSearchEnabled")
        if (json.has("searxUrl")) searxUrl = json.getString("searxUrl")
        if (json.has("huggingFaceToken")) huggingFaceToken = json.getString("huggingFaceToken")
        if (json.has("backend")) backend = json.getString("backend")
        if (json.has("promptTemplate")) promptTemplate = json.getString("promptTemplate")
    }

    private companion object {
        const val KEY_PERSONA = "persona"
        const val KEY_CUSTOM_PROMPT = "custom_prompt"
        const val KEY_MODEL_ID = "model_id"
        const val KEY_TEMPERATURE = "temperature"
        const val KEY_TOP_K = "top_k"
        const val KEY_TOP_P = "top_p"
        const val KEY_MAX_TOKENS = "max_tokens"
        const val KEY_PASSES = "passes"
        const val KEY_SEARCH = "web_search"
        const val KEY_SEARX = "searx_url"
        const val KEY_HF_TOKEN = "hf_token"
        const val KEY_BACKEND = "backend"
        const val KEY_TEMPLATE = "prompt_template"
    }
}
