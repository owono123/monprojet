package com.monprojet.ia.bridge

import android.content.Context
import android.webkit.JavascriptInterface
import com.monprojet.ia.data.ConversationStore
import com.monprojet.ia.data.Personas
import com.monprojet.ia.data.Settings
import com.monprojet.ia.engine.DeliberationSink
import com.monprojet.ia.engine.Deliberator
import com.monprojet.ia.engine.ModelRuntime
import com.monprojet.ia.engine.ROLE_ASSISTANT
import com.monprojet.ia.engine.ROLE_USER
import com.monprojet.ia.engine.Turn
import com.monprojet.ia.export.ProjectExporter
import com.monprojet.ia.model.ModelCatalog
import com.monprojet.ia.model.ModelDownloader
import com.monprojet.ia.model.ModelStore
import com.monprojet.ia.search.WebSearch
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/**
 * Surface appelable depuis la page de chat, exposee sous le nom `Android`.
 *
 * Les methodes sont invoquees depuis un fil de la WebView, jamais depuis le fil principal :
 * tout travail long part dans une coroutine et les resultats reviennent par [WebChannel].
 */
class ChatBridge(
    private val context: Context,
    private val scope: CoroutineScope,
    private val channel: WebChannel,
    private val settings: Settings,
    private val runtime: ModelRuntime,
    private val host: Host,
) {

    /** Ce que le pont ne peut pas faire seul et qui demande l'Activity. */
    interface Host {
        /** Ouvre le selecteur de fichiers pour importer un .task deja telecharge. */
        fun pickModelFile()

        /** Ouvre le partage systeme pour l'archive exportee. */
        fun shareFile(path: String)
    }

    private val store = ModelStore(context)
    private val downloader = ModelDownloader(store)
    private val conversations = ConversationStore(context)
    private val exporter = ProjectExporter(context)
    private val search = WebSearch(settings)
    private val deliberator = Deliberator(runtime)

    private var generationJob: Job? = null
    private var downloadJob: Job? = null
    private var activationJob: Job? = null

    // --- Conversation -------------------------------------------------------------

    /**
     * @param historyJson tours precedents de la conversation, au format
     *   `[{"role":"user","content":"…"}]`. Sans eux le modele repartirait de zero a chaque
     *   message : la session d'inference est recreee pour chaque reponse.
     */
    @JavascriptInterface
    fun send(requestId: String, prompt: String, historyJson: String) {
        // Une seule generation a la fois : le modele local n'a pas la memoire pour deux.
        generationJob?.cancel()
        generationJob = scope.launch(Dispatchers.Default) {
            try {
                var question = prompt

                if (settings.webSearchEnabled) {
                    channel.emit(
                        "step",
                        JSONObject().put("id", requestId).put("label", "Recherche web"),
                    )
                    val (contextText, results) = search.buildContext(prompt)
                    if (results.isNotEmpty()) {
                        question = "$contextText\nQuestion : $prompt"
                        channel.emit(
                            "sources",
                            JSONObject().put("id", requestId).put(
                                "results",
                                JSONArray().apply {
                                    results.forEach {
                                        put(
                                            JSONObject()
                                                .put("title", it.title)
                                                .put("url", it.url)
                                        )
                                    }
                                },
                            ),
                        )
                    }
                }

                deliberator.run(
                    systemPrompt = settings.effectiveSystemPrompt(),
                    history = parseHistory(historyJson),
                    userMessage = question,
                    passes = settings.deliberationPasses,
                    sink = object : DeliberationSink {
                        override fun onStepStart(label: String) {
                            channel.emit(
                                "step",
                                JSONObject().put("id", requestId).put("label", label),
                            )
                        }

                        override fun onStepToken(text: String) {
                            channel.emit(
                                "stepToken",
                                JSONObject().put("id", requestId).put("text", text),
                            )
                        }

                        override fun onAnswerToken(text: String) {
                            channel.emitToken(requestId, text)
                        }
                    },
                )
                channel.emitDone(requestId)
            } catch (e: CancellationException) {
                channel.emitDone(requestId)
                throw e
            } catch (e: Exception) {
                channel.emitError(requestId, e.message ?: e.javaClass.simpleName)
            }
        }
    }

    @JavascriptInterface
    fun stop() {
        generationJob?.cancel()
    }

    private fun parseHistory(json: String): List<Turn> {
        if (json.isBlank()) return emptyList()
        val array = runCatching { JSONArray(json) }.getOrNull() ?: return emptyList()
        val turns = mutableListOf<Turn>()
        for (i in 0 until array.length()) {
            val item = array.optJSONObject(i) ?: continue
            val content = item.optString("content")
            if (content.isEmpty()) continue
            val role = if (item.optString("role") == ROLE_ASSISTANT) ROLE_ASSISTANT else ROLE_USER
            turns += Turn(role, content)
        }
        return turns
    }

    // --- Etat et reglages ---------------------------------------------------------

    @JavascriptInterface
    fun getState(): String = JSONObject()
        .put("modelReady", runtime.isReady)
        .put("modelLoading", runtime.isLoading)
        .put("currentModelId", runtime.currentModelId ?: "")
        .put("ramMb", ModelCatalog.totalRamMb(context))
        .put("freeSpaceMb", store.freeSpaceBytes() / (1024 * 1024))
        .put("recommendedModelId", ModelCatalog.recommendedFor(context).id)
        .put("models", ModelCatalog.toJson(context))
        .put("installedModelIds", JSONArray(store.installedIds()))
        .put("personas", Personas.toJson())
        .put("settings", settings.toJson())
        .toString()

    @JavascriptInterface
    fun updateSettings(json: String) {
        settings.apply(JSONObject(json))
        channel.emit("state", JSONObject().put("state", getState()))
    }

    // --- Modeles ------------------------------------------------------------------

    @JavascriptInterface
    fun downloadModel(modelId: String) {
        val spec = ModelCatalog.byId(modelId) ?: return
        downloadJob?.cancel()
        downloadJob = scope.launch(Dispatchers.IO) {
            try {
                emitDownload(modelId, "start", 0, spec.approxBytes, "")
                val file = downloader.download(spec, settings.huggingFaceToken) { progress ->
                    emitDownload(
                        modelId, "progress",
                        progress.downloadedBytes, progress.totalBytes, "",
                    )
                }
                emitDownload(modelId, "done", file.length(), file.length(), "")
                activate(modelId)
            } catch (e: CancellationException) {
                emitDownload(modelId, "cancelled", 0, 0, "")
                throw e
            } catch (e: Exception) {
                emitDownload(modelId, "error", 0, 0, e.message ?: "Echec du telechargement")
            }
        }
    }

    @JavascriptInterface
    fun cancelDownload() {
        downloadJob?.cancel()
    }

    @JavascriptInterface
    fun importModel() {
        host.pickModelFile()
    }

    @JavascriptInterface
    fun deleteModel(modelId: String) {
        scope.launch(Dispatchers.Default) {
            if (runtime.currentModelId == modelId) runtime.unload()
            store.delete(modelId)
            channel.emit("state", JSONObject().put("state", getState()))
        }
    }

    /**
     * Charge un modele deja installe et le retient comme choix courant.
     *
     * Un appui repete pendant le chargement ne relance rien : le travail en cours est
     * conserve, et deux chargements simultanes fermeraient le moteur natif l'un sous
     * l'autre.
     */
    @JavascriptInterface
    fun activateModel(modelId: String) {
        val current = activationJob
        if (current != null && current.isActive) {
            channel.emit("modelLoading", JSONObject().put("id", modelId))
            return
        }
        activationJob = scope.launch(Dispatchers.Default) { activate(modelId) }
    }

    private suspend fun activate(modelId: String) {
        val spec = ModelCatalog.byId(modelId)
        if (spec == null) {
            channel.emit(
                "modelError",
                JSONObject().put("id", modelId).put("message", "Modele inconnu : $modelId"),
            )
            return
        }
        try {
            channel.emit("modelLoading", JSONObject().put("id", modelId))
            runtime.load(spec, store.fileFor(modelId))
            settings.modelId = modelId
            channel.emit("state", JSONObject().put("state", getState()))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            // Les exceptions natives de MediaPipe ont souvent un message nul : sans le nom
            // de la classe, la cause et l'etat du fichier, l'erreur est inexploitable.
            channel.emit(
                "modelError",
                JSONObject().put("id", modelId).put("message", describe(e, modelId)),
            )
        }
    }

    /** Message d'erreur assez precis pour distinguer fichier invalide, memoire et refus. */
    private fun describe(e: Throwable, modelId: String): String {
        val file = store.fileFor(modelId)
        val size = if (file.isFile) "${file.length() / (1024 * 1024)} Mo" else "fichier absent"

        val detail = buildString {
            append(e.javaClass.simpleName)
            e.message?.takeIf { it.isNotBlank() }?.let { append(" : ").append(it) }
            var cause = e.cause
            var depth = 0
            while (cause != null && depth < 3) {
                append(" | cause ").append(cause.javaClass.simpleName)
                cause.message?.takeIf { it.isNotBlank() }?.let { append(" : ").append(it) }
                cause = cause.cause
                depth++
            }
        }
        return "$detail (modele $modelId, $size)"
    }

    private fun emitDownload(id: String, phase: String, done: Long, total: Long, message: String) {
        channel.emit(
            "download",
            JSONObject()
                .put("id", id)
                .put("phase", phase)
                .put("downloaded", done)
                .put("total", total)
                .put("message", message),
        )
    }

    // --- Historique ---------------------------------------------------------------

    @JavascriptInterface
    fun listConversations(): String = conversations.list().toString()

    @JavascriptInterface
    fun loadConversation(id: String): String = conversations.load(id)?.toString() ?: ""

    @JavascriptInterface
    fun saveConversation(id: String, title: String, messagesJson: String) {
        conversations.save(id, title, JSONArray(messagesJson))
    }

    @JavascriptInterface
    fun deleteConversation(id: String) {
        conversations.delete(id)
    }

    // --- Export -------------------------------------------------------------------

    @JavascriptInterface
    fun exportProject(markdown: String, baseName: String) {
        scope.launch(Dispatchers.IO) {
            try {
                val entries = exporter.parse(markdown)
                if (entries.isEmpty()) {
                    channel.emit(
                        "export",
                        JSONObject().put("ok", false).put(
                            "message",
                            "Aucun fichier trouve. Les blocs de code doivent porter " +
                                "« path=chemin/du/fichier » sur leur ligne d'ouverture.",
                        ),
                    )
                    return@launch
                }
                val safeName = baseName.filter { it.isLetterOrDigit() || it == '-' || it == '_' }
                    .ifEmpty { "projet" }
                val zip = exporter.writeZip(entries, safeName)
                channel.emit(
                    "export",
                    JSONObject().put("ok", true).put("count", entries.size)
                        .put("path", zip.absolutePath),
                )
                host.shareFile(zip.absolutePath)
            } catch (e: Exception) {
                channel.emit(
                    "export",
                    JSONObject().put("ok", false).put("message", e.message ?: "Export impossible"),
                )
            }
        }
    }

    // --- Cycle de vie -------------------------------------------------------------

    fun onModelImported(modelId: String) {
        scope.launch(Dispatchers.Default) { activate(modelId) }
    }

    fun notifyState() {
        channel.emit("state", JSONObject().put("state", getState()))
    }

    fun shutdown() {
        generationJob?.cancel()
        downloadJob?.cancel()
        activationJob?.cancel()
        runtime.closeNow()
    }
}
