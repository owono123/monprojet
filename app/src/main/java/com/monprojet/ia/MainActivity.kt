package com.monprojet.ia

import android.annotation.SuppressLint
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.webkit.WebView
import android.widget.Toast
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.monprojet.ia.bridge.ChatBridge
import com.monprojet.ia.bridge.WebChannel
import com.monprojet.ia.data.Settings
import com.monprojet.ia.engine.ModelRuntime
import com.monprojet.ia.model.ModelCatalog
import com.monprojet.ia.model.ModelStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Hote de l'application : une seule Activity qui affiche l'interface de chat, ecrite en
 * HTML/CSS/JS et embarquee dans les assets. Aucun contenu distant n'est charge dans la
 * WebView : tout vient de file:///android_asset/web/.
 */
class MainActivity : AppCompatActivity(), ChatBridge.Host {

    private lateinit var webView: WebView
    private lateinit var bridge: ChatBridge
    private lateinit var settings: Settings
    private lateinit var store: ModelStore

    private val pickModel = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) importModel(uri)
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        settings = Settings(this)
        store = ModelStore(this)
        val runtime = ModelRuntime(this, settings)

        webView = WebView(this).apply {
            this.settings.javaScriptEnabled = true
            this.settings.domStorageEnabled = true
            // La page n'a acces ni aux fichiers ni au reseau : le pont Kotlin reste le
            // seul point de sortie de l'application.
            this.settings.allowFileAccess = false
            this.settings.allowContentAccess = false
            this.settings.blockNetworkLoads = true
            this.settings.textZoom = 100
        }
        setContentView(webView)

        if (BuildConfig.DEBUG) {
            WebView.setWebContentsDebuggingEnabled(true)
        }

        val channel = WebChannel(webView)
        bridge = ChatBridge(this, lifecycleScope, channel, settings, runtime, this)
        webView.addJavascriptInterface(bridge, "Android")
        webView.loadUrl("file:///android_asset/web/index.html")

        restoreLastModel()

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

    /** Recharge au demarrage le modele choisi lors de la session precedente. */
    private fun restoreLastModel() {
        val modelId = settings.modelId
        if (modelId.isNotEmpty() && store.isInstalled(modelId)) {
            bridge.activateModel(modelId)
        }
    }

    private fun importModel(uri: Uri) {
        lifecycleScope.launch {
            val id = ModelCatalog.IMPORTED_ID
            val result = withContext(Dispatchers.IO) {
                runCatching { store.importFrom(uri, id) { } }
            }
            result.fold(
                onSuccess = {
                    settings.modelId = id
                    bridge.onModelImported(id)
                },
                onFailure = {
                    toast("Import impossible : ${it.message}")
                },
            )
        }
    }

    // --- ChatBridge.Host ----------------------------------------------------------

    override fun pickModelFile() {
        // Le selecteur doit demarrer sur le fil principal ; le pont est appele depuis la
        // WebView, sur un autre fil.
        runOnUiThread {
            // Les .task ne sont associes a aucun type MIME connu du systeme.
            pickModel.launch(arrayOf("*/*"))
        }
    }

    override fun shareFile(path: String) {
        runOnUiThread {
            val file = File(path)
            if (!file.isFile) return@runOnUiThread
            val intent = com.monprojet.ia.export.ProjectExporter(this).shareIntent(file)
            startActivity(Intent.createChooser(intent, "Partager l'archive"))
        }
    }

    private fun toast(message: String) {
        runOnUiThread { Toast.makeText(this, message, Toast.LENGTH_LONG).show() }
    }

    override fun onDestroy() {
        bridge.shutdown()
        webView.destroy()
        super.onDestroy()
    }
}
