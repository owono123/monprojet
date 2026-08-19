package com.monprojet.ia.engine

import kotlinx.coroutines.delay

/**
 * Moteur de remplacement utilise tant qu'aucun modele n'est installe. Il ne repond rien
 * d'intelligent : il sert a verifier sur l'appareil que le streaming, l'affichage et le
 * bouton d'arret fonctionnent avant d'ajouter l'inference.
 */
class EchoEngine : LlmEngine {

    override val isReady: Boolean = false

    override suspend fun generate(prompt: String, onToken: (String) -> Unit) {
        val reponse = "Aucun modele n'est encore installe sur cet appareil. " +
            "Cette reponse est generee localement pour verifier l'affichage. " +
            "Ta question faisait ${prompt.trim().length} caracteres."
        for (mot in reponse.split(" ")) {
            onToken("$mot ")
            delay(40)
        }
    }

    override fun close() = Unit
}
