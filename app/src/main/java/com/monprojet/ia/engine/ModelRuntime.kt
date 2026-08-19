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
     * Applique le format de dialogue attendu par le modele a un echange complet. Sans les
     * marqueurs de tour, un modele instruit repond souvent a cote : ils font partie de son
     * entrainement. Et sans les tours precedents, il oublie ce qui vient d'etre dit — la
     * session d'inference est recreee a chaque reponse.
     */
    fun formatPrompt(systemPrompt: String, turns: List<Turn>): String {
        val format = when (settings.promptTemplate) {
            "chatml" -> ChatFormat.CHATML
            "gemma" -> ChatFormat.GEMMA
            "aucun" -> ChatFormat.PLAIN
            else -> loadedSpec?.format ?: ChatFormat.PLAIN
        }

        val kept = trimToBudget(turns)

        return when (format) {
            ChatFormat.CHATML -> buildString {
                append("<|im_start|>system\n").append(systemPrompt).append("<|im_end|>\n")
                for (turn in kept) {
                    val role = if (turn.role == ROLE_USER) "user" else "assistant"
                    append("<|im_start|>").append(role).append("\n")
                    append(turn.content).append("<|im_end|>\n")
                }
                append("<|im_start|>assistant\n")
            }

            ChatFormat.GEMMA -> buildString {
                // Gemma n'a pas de tour systeme : la consigne est placee en tete du premier
                // message de l'utilisateur.
                var systemPlaced = false
                for (turn in kept) {
                    if (turn.role == ROLE_USER) {
                        append("<start_of_turn>user\n")
                        if (!systemPlaced) {
                            append(systemPrompt).append("\n\n")
                            systemPlaced = true
                        }
                        append(turn.content).append("<end_of_turn>\n")
                    } else {
                        append("<start_of_turn>model\n")
                        append(turn.content).append("<end_of_turn>\n")
                    }
                }
                append("<start_of_turn>model\n")
            }

            ChatFormat.PLAIN -> buildString {
                append(systemPrompt).append("\n\n")
                for (turn in kept) {
                    append(if (turn.role == ROLE_USER) "Question : " else "Reponse : ")
                    append(turn.content).append("\n\n")
                }
                append("Reponse : ")
            }
        }
    }

    /** Raccourci pour une consigne isolee, sans historique. */
    fun formatPrompt(systemPrompt: String, userMessage: String): String =
        formatPrompt(systemPrompt, listOf(Turn(ROLE_USER, userMessage)))

    /**
     * Ne garde que la fin de la conversation. Le contexte du modele est court et il est
     * fixe au chargement : deborder ne provoque pas une erreur claire mais une reponse
     * tronquee ou incoherente. Le dernier message, celui auquel il faut repondre, est
     * toujours conserve.
     */
    private fun trimToBudget(turns: List<Turn>): List<Turn> {
        if (turns.isEmpty()) return turns

        // Environ quatre caracteres par token, et on laisse la moitie du contexte pour la
        // reponse elle-meme.
        val budget = settings.maxTokens * 4 / 2
        val kept = ArrayDeque<Turn>()
        var used = 0

        for (turn in turns.asReversed()) {
            val cost = turn.content.length + MARKER_COST
            if (kept.isNotEmpty() && used + cost > budget) break
            kept.addFirst(turn)
            used += cost
        }
        return kept
    }

    private companion object {
        const val TAG = "ModelRuntime"
        const val MARKER_COST = 16
    }
}
