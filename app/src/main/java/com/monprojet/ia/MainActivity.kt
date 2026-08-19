package com.monprojet.ia

import android.annotation.SuppressLint
import android.os.Bundle
import android.webkit.WebView
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.monprojet.ia.bridge.ChatBridge
import com.monprojet.ia.bridge.WebChannel
import com.monprojet.ia.engine.EchoEngine

/**
 * Hote de l'application : une seule Activity qui affiche l'interface de chat, ecrite en
 * HTML/CSS/JS et embarquee dans les assets. Aucun contenu distant n'est charge dans la
 * WebView, tout vient de file:///android_asset/web/.
 */
class MainActivity : AppCompatActivity() {

    private lateinit var webView: WebView
    private lateinit var bridge: ChatBridge

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        webView = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            // Aucun acces au systeme de fichiers ni au reseau depuis la page elle-meme :
            // tout passe par le pont Kotlin, qui reste le seul point de sortie.
            settings.allowFileAccess = false
            settings.allowContentAccess = false
            settings.blockNetworkLoads = true
            settings.textZoom = 100
        }
        setContentView(webView)

        if (BuildConfig.DEBUG) {
            WebView.setWebContentsDebuggingEnabled(true)
        }

        val channel = WebChannel(webView)
        bridge = ChatBridge(lifecycleScope, channel, EchoEngine())
        webView.addJavascriptInterface(bridge, "Android")
        webView.loadUrl("file:///android_asset/web/index.html")

        // Le bouton retour ferme d'abord un panneau ouvert cote interface ; l'application
        // ne se ferme que si la page n'a rien a fermer.
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                webView.evaluateJavascript("window.iaHandleBack && window.iaHandleBack()") { result ->
                    if (result != "true") {
                        isEnabled = false
                        onBackPressedDispatcher.onBackPressed()
                    }
                }
            }
        })
    }

    override fun onDestroy() {
        bridge.shutdown()
        webView.destroy()
        super.onDestroy()
    }
}
