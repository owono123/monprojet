package com.monprojet.ia.search

import com.monprojet.ia.data.Settings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.BufferedReader
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * Recherche web facultative. C'est la seule fonction de l'application qui sorte de
 * l'appareil, et elle est desactivee par defaut : tant qu'elle est eteinte, aucune requete
 * ne part pendant une conversation.
 *
 * Deux sources possibles : une instance SearXNG personnelle, qui rend du JSON propre et ne
 * partage rien avec un tiers, ou DuckDuckGo Lite par defaut. La seconde impose d'analyser
 * du HTML, ce qui peut casser si la page change de forme ; l'erreur est alors remontee
 * telle quelle plutot que silencieuse.
 */
class WebSearch(private val settings: Settings) {

    data class Result(val title: String, val url: String, val snippet: String)

    suspend fun search(query: String, max: Int = 3): List<Result> = withContext(Dispatchers.IO) {
        val searx = settings.searxUrl.trim()
        if (searx.isNotEmpty()) searchSearx(searx, query, max) else searchDuckDuckGo(query, max)
    }

    /**
     * Construit un bloc de contexte a injecter avant la question, avec les sources
     * numerotees pour que le modele puisse y renvoyer.
     */
    suspend fun buildContext(query: String, max: Int = 3): Pair<String, List<Result>> {
        val results = search(query, max)
        if (results.isEmpty()) return "" to emptyList()

        val text = buildString {
            appendLine("Resultats de recherche web, a utiliser pour repondre :")
            results.forEachIndexed { index, r ->
                appendLine()
                appendLine("[${index + 1}] ${r.title} — ${r.url}")
                appendLine(r.snippet.take(SNIPPET_LIMIT))
            }
            appendLine()
            appendLine("Cite la source entre crochets quand tu t'en sers, par exemple [1].")
        }
        return text to results
    }

    private fun searchSearx(baseUrl: String, query: String, max: Int): List<Result> {
        val url = baseUrl.trimEnd('/') + "/search?format=json&q=" + encode(query)
        val body = fetch(url) ?: return emptyList()
        val array = JSONObject(body).optJSONArray("results") ?: return emptyList()
        val results = mutableListOf<Result>()
        for (i in 0 until minOf(array.length(), max)) {
            val item = array.getJSONObject(i)
            results += Result(
                title = item.optString("title"),
                url = item.optString("url"),
                snippet = item.optString("content"),
            )
        }
        return results
    }

    private fun searchDuckDuckGo(query: String, max: Int): List<Result> {
        val body = fetch("https://html.duckduckgo.com/html/?q=" + encode(query))
            ?: return emptyList()

        val results = mutableListOf<Result>()
        for (match in RESULT_LINK.findAll(body)) {
            if (results.size >= max) break
            val href = decodeRedirect(match.groupValues[1])
            val title = stripTags(match.groupValues[2])
            if (href.isBlank() || title.isBlank()) continue
            results += Result(title = title, url = href, snippet = "")
        }

        // Les extraits arrivent dans un bloc distinct du titre : on les rapproche par rang.
        val snippets = SNIPPET.findAll(body).map { stripTags(it.groupValues[1]) }.toList()
        return results.mapIndexed { index, r ->
            if (index < snippets.size) r.copy(snippet = snippets[index]) else r
        }
    }

    private fun fetch(url: String): String? {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            instanceFollowRedirects = true
            connectTimeout = 15_000
            readTimeout = 20_000
            // Sans un agent utilisateur credible, DuckDuckGo renvoie une page vide.
            setRequestProperty("User-Agent", USER_AGENT)
            setRequestProperty("Accept-Language", "fr,en;q=0.8")
        }
        return try {
            if (connection.responseCode !in 200..299) return null
            connection.inputStream.bufferedReader().use(BufferedReader::readText)
        } catch (e: Exception) {
            null
        } finally {
            connection.disconnect()
        }
    }

    /** DuckDuckGo enveloppe les liens dans une redirection : on recupere l'adresse reelle. */
    private fun decodeRedirect(href: String): String {
        val marker = "uddg="
        val start = href.indexOf(marker)
        if (start < 0) return href
        val raw = href.substring(start + marker.length).substringBefore('&')
        return runCatching { java.net.URLDecoder.decode(raw, "UTF-8") }.getOrDefault(href)
    }

    private fun stripTags(html: String): String =
        html.replace(TAG, " ")
            .replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
            .replace("&quot;", "\"").replace("&#x27;", "'").replace("&nbsp;", " ")
            .replace(WHITESPACE, " ")
            .trim()

    private fun encode(value: String): String = URLEncoder.encode(value, "UTF-8")

    private companion object {
        const val SNIPPET_LIMIT = 600
        const val USER_AGENT =
            "Mozilla/5.0 (Linux; Android 9) AppleWebKit/537.36 (KHTML, like Gecko) Mobile Safari/537.36"

        val RESULT_LINK = Regex("""<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>""", RegexOption.DOT_MATCHES_ALL)
        val SNIPPET = Regex("""<a[^>]*class="result__snippet"[^>]*>(.*?)</a>""", RegexOption.DOT_MATCHES_ALL)
        val TAG = Regex("<[^>]*>")
        val WHITESPACE = Regex("\\s+")
    }
}
