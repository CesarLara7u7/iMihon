package mihon.shared.source

import io.ktor.http.encodeURLQueryComponent
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Fuente nativa de **MangaFire** (mangafire.to). Scraper de HTML tras Cloudflare con un token
 * `vrf` generado por su JavaScript e imágenes barajadas.
 *
 * - **Cloudflare + vrf**: las peticiones pasan por un [WebFetcher] (WKWebView). Popular/recientes
 *   (`/filter?sort=`) y detalle/capítulos NO necesitan vrf (HTML/JSON directo). La **búsqueda** y
 *   la **lista de páginas** sí: se captura la URL firmada que dispara el propio sitio.
 * - **Imágenes barajadas**: si la página trae `offset>0`, la URL lleva `#scrambled_<offset>` y la
 *   capa de imágenes de Swift la des-baraja (rejilla de bloques).
 *
 * @param lang código de idioma de la app; @param langCode el que usa MangaFire (es-419→es-la…).
 */
class MangaFireSource(
    override val lang: String,
    private val langCode: String = lang,
) : MangaSource {

    override val id: String = "mangafire-$lang"
    override val name: String = "MangaFire"
    override val supportsRating: Boolean = false

    private val json = Json { ignoreUnknownKeys = true }

    override suspend fun popular(page: Int): List<BrowseManga> = browse(sort = 0, genreIds = emptyList(), page = page)

    override suspend fun browse(sort: Int, genreIds: List<String>, page: Int): List<BrowseManga> {
        val sortVal = if (sort == 1) "recently_updated" else "most_viewed"
        val url = "$BASE/filter?sort=$sortVal&language%5B%5D=$langCode&page=$page"
        return parseList(fetchWeb(url))
    }

    override suspend fun search(query: String, page: Int): List<BrowseManga> {
        val q = query.trim()
        if (q.isBlank()) return emptyList()
        // El vrf lo genera el JS del sitio al teclear en su buscador: lo capturamos.
        val trigger = "var i=document.querySelector('input[name=keyword]');" +
            "if(i){i.value=${jsString(q)};i.dispatchEvent(new Event('keyup',{bubbles:true}));}"
        val captured = captureWeb("$BASE/home", trigger, "ajax/manga/search")
        val vrf = captured.substringAfter("vrf=", "").substringBefore("&").takeIf { it.isNotBlank() }
            ?: throw Exception("MangaFire: no se obtuvo el token vrf")
        val url = "$BASE/filter?keyword=${q.encodeURLQueryComponent()}&language%5B%5D=$langCode&page=$page&vrf=$vrf"
        return parseList(fetchWeb(url))
    }

    override suspend fun genres(): List<SourceGenre> = emptyList()

    override suspend fun detail(mangaId: String): SourceMangaDetail {
        val html = fetchWeb("$BASE/$mangaId")
        val main = html.substringAfter("main-inner", html)
        return SourceMangaDetail(
            id = mangaId,
            title = firstGroup(html, Regex("<h1[^>]*>([^<]+)</h1>")) ?: "Sin título",
            author = firstGroup(main, Regex("Author:</span>\\s*<span>\\s*<a[^>]*>([^<]+)</a>")),
            artist = null,
            description = synopsis(html),
            genres = Regex("/genre/[^\"]+\"[^>]*>([^<]+)</a>").findAll(genresBlock(main))
                .map { it.groupValues[1].trim() }.toList(),
            status = statusFor(firstGroup(main, Regex("class=\"info\">\\s*<p[^>]*>([^<]+)</p>"))),
            thumbnailUrl = firstGroup(main, Regex("class=\"poster\">\\s*<div>\\s*<img src=\"([^\"]+)\"")),
            inLibrary = false,
        )
    }

    override suspend fun chapters(mangaId: String): List<SourceChapter> {
        val numId = mangaId.substringAfterLast(".")
        val body = fetchWeb("$BASE/ajax/manga/$numId/chapter/$langCode")
        val result = json.parseToJsonElement(body).jsonObject["result"]?.jsonPrimitive?.contentOrNull ?: return emptyList()
        // result es HTML: <li class="item" data-number="N"> <a href="/read/..." title> <span>nombre</span> <span>fecha</span>
        return Regex("<li[^>]*data-number=\"([^\"]*)\"[^>]*>\\s*<a href=\"([^\"]+)\"[^>]*>(.*?)</a>", RegexOption.DOT_MATCHES_ALL)
            .findAll(result).mapNotNull { m ->
                val number = m.groupValues[1]
                val href = m.groupValues[2].trim('/')
                val inner = m.groupValues[3]
                val spans = Regex("<span>(.*?)</span>", RegexOption.DOT_MATCHES_ALL).findAll(inner)
                    .map { unescape(it.groupValues[1].trim()) }.toList()
                val rawName = spans.getOrNull(0).orEmpty().trimEnd(':', ' ')
                val date = spans.getOrNull(1).orEmpty()
                SourceChapter(
                    id = href,
                    name = rawName.ifBlank { if (number.isNotBlank()) "Capítulo $number" else "Capítulo" },
                    chapterNumber = number.toDoubleOrNull() ?: -1.0,
                    scanlator = null,
                    read = false,
                    bookmark = false,
                    uploadDate = parseDate(date),
                    pageCount = 0,
                )
            }.toList()
    }

    override suspend fun pages(chapterId: String): List<String> {
        // El sitio dispara ajax/read/chapter al cargar la página del capítulo: capturamos su URL (con vrf).
        val ajaxUrl = captureWeb("$BASE/$chapterId", triggerJs = "", urlContains = "ajax/read/chapter")
        val body = fetchWeb(ajaxUrl)
        val images = json.parseToJsonElement(body).jsonObject["result"]?.jsonObject
            ?.get("images") as? JsonArray ?: return emptyList()
        return images.mapNotNull { node ->
            val arr = node.jsonArray
            val url = arr.getOrNull(0)?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
            val offset = arr.getOrNull(2)?.jsonPrimitive?.intOrNull ?: 0
            if (offset > 0) "$url#scrambled_$offset" else url
        }
    }

    override suspend fun recentUpdates(): List<RecentUpdate> = emptyList()

    // MARK: - Red (vía WebView)

    private suspend fun fetchWeb(url: String): String = suspendCancellableCoroutine { cont ->
        val f = SourceRegistry.webFetcher
            ?: return@suspendCancellableCoroutine cont.resumeWithException(Exception("MangaFire requiere WebView"))
        f.fetch(url, { if (cont.isActive) cont.resume(it) }, { if (cont.isActive) cont.resumeWithException(Exception(it)) })
    }

    private suspend fun captureWeb(pageUrl: String, triggerJs: String, urlContains: String): String =
        suspendCancellableCoroutine { cont ->
            val f = SourceRegistry.webFetcher
                ?: return@suspendCancellableCoroutine cont.resumeWithException(Exception("MangaFire requiere WebView"))
            f.capture(pageUrl, triggerJs, urlContains,
                { if (cont.isActive) cont.resume(it) },
                { if (cont.isActive) cont.resumeWithException(Exception(it)) })
        }

    // MARK: - Parseo HTML

    private fun parseList(html: String): List<BrowseManga> =
        Regex("<a href=\"/manga/([^\"]+)\"\\s+class=\"poster\"[^>]*>\\s*<div>\\s*<img src=\"([^\"]+)\"\\s+alt=\"([^\"]*)\"")
            .findAll(html).map { m ->
                BrowseManga(
                    sourceId = id,
                    id = "manga/${m.groupValues[1]}",
                    title = unescape(m.groupValues[3]).ifBlank { "Sin título" },
                    thumbnailUrl = m.groupValues[2],
                    inLibrary = false,
                )
            }.toList()

    private fun synopsis(html: String): String? {
        val start = html.indexOf("id=\"synopsis\"")
        if (start < 0) return null
        val contentIdx = html.indexOf("modal-content", start)
        if (contentIdx < 0) return null
        // El texto va tras el botón de cierre del modal; quitamos etiquetas.
        val region = html.substring(contentIdx, (contentIdx + 4000).coerceAtMost(html.length))
        val afterClose = region.substringAfter("modal-close", region).substringAfter("</div>", region)
        val text = afterClose.substringBefore("</div>")
        return unescape(text.replace(Regex("<[^>]+>"), " ").replace(Regex("\\s+"), " ")).trim().ifBlank { null }
    }

    private fun genresBlock(main: String): String {
        val i = main.indexOf("Genres:</span>")
        if (i < 0) return ""
        return main.substring(i, (i + 800).coerceAtMost(main.length))
    }

    private fun firstGroup(text: String, regex: Regex): String? =
        regex.find(text)?.groupValues?.getOrNull(1)?.let { unescape(it).trim() }?.ifBlank { null }

    private fun statusFor(status: String?): String = when (status?.lowercase()?.trim()) {
        "releasing" -> "ONGOING"
        "completed" -> "COMPLETED"
        "on_hiatus" -> "ON_HIATUS"
        "discontinued" -> "CANCELLED"
        else -> "UNKNOWN"
    }

    /** Fecha "MMM dd, yyyy" → millis (día); "X ago"/relativas → 0. Sin dependencias. */
    private fun parseDate(s: String): Long {
        val m = Regex("([A-Za-z]{3}) (\\d{1,2}), (\\d{4})").find(s) ?: return 0
        val month = MONTHS.indexOf(m.groupValues[1]) + 1
        if (month == 0) return 0
        val day = m.groupValues[2].toIntOrNull() ?: return 0
        val year = m.groupValues[3].toIntOrNull() ?: return 0
        val yy = if (month <= 2) year - 1 else year
        val era = (if (yy >= 0) yy else yy - 399) / 400
        val yoe = yy - era * 400
        val doy = (153 * (if (month > 2) month - 3 else month + 9) + 2) / 5 + day - 1
        val doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return (era.toLong() * 146097 + doe - 719468) * 86_400_000L
    }

    private fun jsString(s: String): String =
        "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", " ") + "\""

    private fun unescape(s: String): String = s
        .replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
        .replace("&quot;", "\"").replace("&#039;", "'").replace("&#39;", "'").replace("&nbsp;", " ")

    companion object {
        private const val BASE = "https://mangafire.to"
        private val MONTHS = listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
    }
}
