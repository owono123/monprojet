package com.monprojet.ia.engine

import android.content.Context
import android.util.Log
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.google.mediapipe.tasks.genai.llminference.LlmInferenceSession
import com.monprojet.ia.data.Settings
import com.monprojet.ia.model.ModelSpec
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.resume

/**
 * Inference locale, via MediaPipe LLM Inference. Tout se passe sur l'appareil : le fichier
 * de modele est lu depuis le stockage prive de l'application et rien n'est envoye sur le
 * reseau.
 */
class ModelRuntime(
    private val context: Context,
    private val settings: Settings,
) {

    private var inference: LlmInference? = null
    private var loadedSpec: ModelSpec? = null

    val isReady: Boolean get() = inference != null
    val currentModelId: String? get() = loadedSpec?.id

    /**
     * Charge un modele en memoire. Operation lourde (plusieurs secondes sur un appareil
     * ancien) : a appeler hors du fil principal.
     */
    suspend fun load(spec: ModelSpec, file: File) = withContext(Dispatchers.Default) {
        require(file.isFile && file.length() > 0) { "Fichier de modele absent ou vide" }
        unload()

        val backend = if (settings.backend == "GPU") {
            LlmInference.Backend.GPU
        } else {
            // Le processeur est le choix sur : beaucoup d'appareils sous Android 9 n'ont
            // pas de pilote OpenCL utilisable par le moteur.
            LlmInference.Backend.CPU
        }

        val options = LlmInference.LlmInferenceOptions.builder()
            .setModelPath(file.absolutePath)
            .setMaxTokens(settings.maxTokens)
            .setPreferredBackend(backend)
            .build()

        inference = LlmInference.createFromOptions(context, options)
        loadedSpec = spec
        Log.i(TAG, "Modele charge : ${spec.id} (${backend})")
    }

    fun unload() {
        runCatching { inference?.close() }
            .onFailure { Log.w(TAG, "Fermeture du modele", it) }
        inference = null
        loadedSpec = null
    }

    /**
     * Genere une reponse pour [prompt] deja formate, en appelant [onToken] au fil de la
     * generation. L'annulation de la coroutine interrompt la generation.
     */
    suspend fun generate(prompt: String, onToken: (String) -> Unit) {
        val engine = inference
            ?: throw IllegalStateException(
                "Aucun modele n'est charge. Ouvre les reglages pour en installer un."
            )

        val sessionOptions = LlmInferenceSession.LlmInferenceSessionOptions.builder()
            .setTopK(settings.topK)
            .setTopP(settings.topP)
            .setTemperature(settings.temperature)
            .build()

        val session = LlmInferenceSession.createFromOptions(engine, sessionOptions)
        try {
            suspendCancellableCoroutine<Unit> { continuation ->
                // Le moteur peut appeler l'ecouteur une derniere fois apres la fin ;
                // ce drapeau garantit qu'on ne reprend la coroutine qu'une seule fois.
                val finished = AtomicBoolean(false)

                session.addQueryChunk(prompt)
                val future = session.generateResponseAsync { partial, done ->
                    if (partial != null && partial.isNotEmpty()) onToken(partial)
                    if (done && finished.compareAndSet(false, true)) {
                        continuation.resume(Unit)
                    }
                }

                continuation.invokeOnCancellation {
                    runCatching { future.cancel(true) }
                }
            }
        } finally {
            runCatching { session.close() }
        }
    }

    /**
     * Applique le format de dialogue attendu par le modele. Sans lui, un modele instruit
     * repond souvent a cote : les marqueurs de tour font partie de son entrainement.
     */
    fun formatPrompt(systemPrompt: String, userMessage: String): String {
        val template = when (settings.promptTemplate) {
            "chatml" -> CHATML
            "gemma" -> GEMMA
            "aucun" -> null
            else -> loadedSpec?.promptTemplate
        } ?: return "$systemPrompt\n\n$userMessage"

        return template
            .replace("{system}", systemPrompt)
            .replace("{user}", userMessage)
    }

    private companion object {
        const val TAG = "ModelRuntime"

        const val CHATML = "<|im_start|>system\n{system}<|im_end|>\n" +
            "<|im_start|>user\n{user}<|im_end|>\n<|im_start|>assistant\n"

        const val GEMMA = "<start_of_turn>user\n{system}\n\n{user}<end_of_turn>\n" +
            "<start_of_turn>model\n"
    }
}
