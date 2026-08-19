package com.monprojet.ia.bridge

import android.webkit.JavascriptInterface
import com.monprojet.ia.engine.LlmEngine
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * Surface appelable depuis la page de chat. Chaque methode annotee @JavascriptInterface est
 * exposee sous le nom `Android` cote JavaScript.
 */
class ChatBridge(
    private val scope: CoroutineScope,
    private val channel: WebChannel,
    private val engine: LlmEngine,
) {

    private var currentJob: Job? = null

    @JavascriptInterface
    fun send(requestId: String, prompt: String) {
        // Une seule generation a la fois : le modele local n'a pas la memoire pour deux.
        currentJob?.cancel()
        currentJob = scope.launch(Dispatchers.Default) {
            try {
                engine.generate(prompt) { token -> channel.emitToken(requestId, token) }
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
        currentJob?.cancel()
    }

    /** Etat lu par la page au demarrage pour savoir quoi afficher. */
    @JavascriptInterface
    fun getState(): String = JSONObject()
        .put("modelReady", engine.isReady)
        .toString()

    fun shutdown() {
        currentJob?.cancel()
        engine.close()
    }
}
