package com.monprojet.ia.bridge

import android.webkit.WebView
import org.json.JSONObject

/**
 * Canal Kotlin -> JavaScript. Le payload est transmis comme une chaine JSON echappee puis
 * reparse cote page, ce qui evite toute injection de code depuis le texte du modele.
 */
class WebChannel(private val webView: WebView) {

    fun emit(event: String, payload: JSONObject) {
        val script = "window.__iaEvent(" +
            JSONObject.quote(event) + "," +
            JSONObject.quote(payload.toString()) + ")"
        webView.post { webView.evaluateJavascript(script, null) }
    }

    fun emitToken(requestId: String, token: String) {
        emit("token", JSONObject().put("id", requestId).put("text", token))
    }

    fun emitDone(requestId: String) {
        emit("done", JSONObject().put("id", requestId))
    }

    fun emitError(requestId: String, message: String) {
        emit("error", JSONObject().put("id", requestId).put("message", message))
    }
}
