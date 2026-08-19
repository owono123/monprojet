package com.monprojet.ia.engine

/**
 * Moteur d'inference local. L'implementation reelle (MediaPipe) arrive a l'etape suivante ;
 * l'interface existe des maintenant pour que l'interface de chat et le pont soient
 * testables sur l'appareil avant de manipuler un fichier de modele de plusieurs centaines
 * de megaoctets.
 */
interface LlmEngine {

    /** Vrai quand un modele est charge et pret a repondre. */
    val isReady: Boolean

    /**
     * Genere une reponse pour [prompt] en appelant [onToken] au fil de la generation.
     * La fonction est suspendue et doit etre annulable : l'annulation de la coroutine
     * interrompt la generation.
     */
    suspend fun generate(prompt: String, onToken: (String) -> Unit)

    /** Libere le modele et la memoire associee. */
    fun close()
}
