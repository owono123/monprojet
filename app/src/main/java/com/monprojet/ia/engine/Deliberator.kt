package com.monprojet.ia.engine

/**
 * Recoit le deroulement d'une reflexion multi-passes : les etapes intermediaires vont dans
 * le panneau repliable, seule la reponse finale s'affiche comme message.
 */
interface DeliberationSink {
    fun onStepStart(label: String)
    fun onStepToken(text: String)
    fun onAnswerToken(text: String)
}

/**
 * Fait repasser le modele plusieurs fois sur sa propre reponse : plan, brouillon, critique,
 * puis reecriture. Un petit modele gagne surtout a la critique, ou il repere ses oublis.
 *
 * Le cout est proportionnel : chaque passe est une generation complete, donc trois passes
 * prennent environ quatre fois plus de temps qu'une reponse directe. C'est pour cela que le
 * reglage descend jusqu'a zero, qui rend la reponse immediate.
 */
class Deliberator(private val runtime: ModelRuntime) {

    suspend fun run(
        systemPrompt: String,
        userMessage: String,
        passes: Int,
        sink: DeliberationSink,
    ) {
        if (passes <= 0) {
            runtime.generate(runtime.formatPrompt(systemPrompt, userMessage)) { sink.onAnswerToken(it) }
            return
        }

        sink.onStepStart("Plan")
        val plan = collect(systemPrompt, PLAN_INSTRUCTION.format(userMessage), sink)

        sink.onStepStart("Brouillon")
        var answer = collect(systemPrompt, DRAFT_INSTRUCTION.format(userMessage, plan), sink)

        repeat(passes) { index ->
            sink.onStepStart("Critique ${index + 1}")
            val critique = collect(
                systemPrompt,
                CRITIQUE_INSTRUCTION.format(userMessage, answer),
                sink,
            )

            val isLast = index == passes - 1
            sink.onStepStart(if (isLast) "Reponse finale" else "Reecriture ${index + 1}")
            answer = if (isLast) {
                buildString {
                    runtime.generate(
                        runtime.formatPrompt(
                            systemPrompt,
                            REVISE_INSTRUCTION.format(userMessage, answer, critique),
                        )
                    ) { token ->
                        append(token)
                        sink.onAnswerToken(token)
                    }
                }
            } else {
                collect(systemPrompt, REVISE_INSTRUCTION.format(userMessage, answer, critique), sink)
            }
        }
    }

    private suspend fun collect(
        systemPrompt: String,
        instruction: String,
        sink: DeliberationSink,
    ): String = buildString {
        runtime.generate(runtime.formatPrompt(systemPrompt, instruction)) { token ->
            append(token)
            sink.onStepToken(token)
        }
    }

    private companion object {
        const val PLAN_INSTRUCTION =
            "Question posee :\n%s\n\n" +
                "N'y reponds pas encore. Enumere en trois points maximum ce qu'une bonne " +
                "reponse doit couvrir, et les pieges a eviter."

        const val DRAFT_INSTRUCTION =
            "Question posee :\n%s\n\nPlan a suivre :\n%s\n\n" +
                "Redige maintenant la reponse en suivant ce plan."

        const val CRITIQUE_INSTRUCTION =
            "Question posee :\n%s\n\nReponse proposee :\n%s\n\n" +
                "Relis cette reponse en critique exigeant. Liste uniquement ce qui est " +
                "faux, imprecis ou manquant. Si elle est correcte, ecris seulement : RAS."

        const val REVISE_INSTRUCTION =
            "Question posee :\n%s\n\nReponse precedente :\n%s\n\nCritiques a corriger :\n%s\n\n" +
                "Reecris la reponse complete en tenant compte des critiques. Ne mentionne " +
                "ni le plan, ni les critiques, ni le fait qu'il s'agit d'une reecriture."
    }
}
