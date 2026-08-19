package com.monprojet.ia.engine

/** Format de dialogue attendu par un modele instruit. */
enum class ChatFormat { CHATML, GEMMA, PLAIN }

const val ROLE_USER = "user"
const val ROLE_ASSISTANT = "assistant"

/** Un tour de parole de la conversation. */
data class Turn(val role: String, val content: String)
