package mihon.shared.source

import io.ktor.http.encodeURLQueryComponent
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Fuente nativa de **Comick** (comick.live). Catálogo enorme y multi-idioma con capítulos
 * completos e imágenes sin cifrar (WebP/JPEG en su CDN).
 *
 * Comick está tras **Cloudflare**: la pila TLS nativa recibe el reto JS, así que las peticiones
 * de API y de páginas se enrutan por un [WebFetcher] (WKWebView en iOS) que resuelve el reto.
 * Las **imágenes** sí se bajan con el cliente normal (su CDN solo exige `Referer`).
 *
 * Endpoints JSON: `/api/search`, `/api/metadata`, `/api/comics/{slug}/chapter-list`.
 * Detalle y lista de páginas vienen incrustados en `<script id="comic-data">` / `<script id="sv-data">`.
 */
class ComickSource(override val lang: String) : MangaSource {

    override val id: String = "comick-$lang"
    override val name: String = "Comick"
    override val isNsfw: Boolean = true   // Comick mezcla bastante contenido +18.
    // /api/search (orden por rating, géneros y búsqueda de texto) está blindado por Cloudflare
    // INCLUSO desde el WebView, así que no se ofrece puntuación/filtros/búsqueda en Comick.
    override val supportsRating: Boolean = false

    private val json = Json { ignoreUnknownKeys = true }

    override suspend fun popular(page: Int): List<BrowseManga> = browse(sort = 0, genreIds = emptyList(), page = page)

    override suspend fun browse(sort: Int, genreIds: List<String>, page: Int): List<BrowseManga> =
        if (sort == 1) latest(page) else top(page)

    /** Más seguidos (`/api/comics/top`). Pagina 1..6 variando ventana y tipo (como la extensión). */
    private suspend fun top(page: Int): List<BrowseManga> {
        if (page > 6) return emptyList()
        val days = when (page) { 1, 4 -> 7; 2, 5 -> 30; else -> 90 }
        val type = if (page <= 3) "follow" else "most_follow_new"
        val params = listOf("days" to days.toString(), "type" to type)
        val root = json.parseToJsonElement(ensureJson(fetchWeb(url("/api/comics/top", params)))).jsonObject
        return (root["data"] as? JsonArray).orEmpty().map { it.jsonObject.toBrowseManga() }.distinctBy { it.id }
    }

    /** Últimas actualizaciones (`/api/chapters/latest`); cada entrada trae el cómic. */
    private suspend fun latest(page: Int): List<BrowseManga> {
        val params = listOf("order" to "new", "page" to page.toString())
        val root = json.parseToJsonElement(ensureJson(fetchWeb(url("/api/chapters/latest", params)))).jsonObject
        return (root["data"] as? JsonArray).orEmpty().map { it.jsonObject.toBrowseManga() }
            .filter { it.id.isNotBlank() }.distinctBy { it.id }
    }

    // La búsqueda de texto y los géneros usan /api/search, que Cloudflare bloquea aquí.
    override suspend fun search(query: String, page: Int): List<BrowseManga> = emptyList()

    override suspend fun genres(): List<SourceGenre> = emptyList()

    override suspend fun detail(mangaId: String): SourceMangaDetail {
        val html = fetchWeb("$BASE/comic/$mangaId")
        val data = json.parseToJsonElement(extractEmbeddedJson(html, "comic-data")).jsonObject

        val genres = buildList {
            when (data["country"]?.jsonPrimitive?.contentOrNull) {
                "jp" -> add("Manga"); "cn" -> add("Manhua"); "ko" -> add("Manhwa")
            }
            (data["md_comic_md_genres"] as? JsonArray).orEmpty().forEach { g ->
                g.jsonObject["md_genres"]?.jsonObject?.get("name")?.jsonPrimitive?.contentOrNull?.let { add(it) }
            }
        }
        return SourceMangaDetail(
            id = mangaId,
            title = data["title"]?.jsonPrimitive?.contentOrNull ?: "Sin título",
            author = (data["authors"] as? JsonArray).orEmpty().names(),
            artist = (data["artists"] as? JsonArray).orEmpty().names(),
            description = data["desc"]?.jsonPrimitive?.contentOrNull
                ?.replace(Regex("<[^>]+>"), " ")?.replace(Regex("\\s+"), " ")?.trim(),
            genres = genres,
            status = statusFor(data["status"]?.jsonPrimitive?.intOrNull),
            thumbnailUrl = data["default_thumbnail"]?.jsonPrimitive?.contentOrNull,
            inLibrary = false,
        )
    }

    override suspend fun chapters(mangaId: String): List<SourceChapter> {
        // El catálogo de Comick es global (dominado por inglés) y los capítulos se filtran por
        // idioma. Si la fuente (p. ej. Español) no tiene capítulos para este título, recurrimos
        // a inglés (lo más común) para no mostrar "0 capítulos".
        val own = chaptersForLang(mangaId, lang)
        return own.ifEmpty { if (lang != "en") chaptersForLang(mangaId, "en") else own }
    }

    private suspend fun chaptersForLang(mangaId: String, chapterLang: String): List<SourceChapter> {
        val out = mutableListOf<SourceChapter>()
        var page = 1
        var lastPage = 1
        do {
            val u = url("/api/comics/$mangaId/chapter-list", listOf("lang" to chapterLang, "page" to page.toString()))
            val root = json.parseToJsonElement(ensureJson(fetchWeb(u))).jsonObject
            lastPage = root["pagination"]?.jsonObject?.get("last_page")?.jsonPrimitive?.intOrNull ?: 1
            (root["data"] as? JsonArray).orEmpty().forEach { node ->
                val c = node.jsonObject
                val hid = c["hid"]?.jsonPrimitive?.contentOrNull ?: return@forEach
                val chap = c["chap"]?.jsonPrimitive?.contentOrNull ?: ""
                val chLang = c["lang"]?.jsonPrimitive?.contentOrNull ?: chapterLang
                val vol = c["vol"]?.jsonPrimitive?.contentOrNull
                val titleText = c["title"]?.jsonPrimitive?.contentOrNull
                val groups = (c["group_name"] as? JsonArray).orEmpty()
                    .mapNotNull { it.jsonPrimitive.contentOrNull }
                out += SourceChapter(
                    // El id codifica la ruta del capítulo para reconstruir su página en pages().
                    id = "comic/$mangaId/$hid-chapter-$chap-$chLang",
                    name = buildString {
                        if (!vol.isNullOrBlank()) append("Vol. $vol ")
                        append(if (chap.isBlank()) "Oneshot" else "Cap. $chap")
                        if (!titleText.isNullOrBlank()) append(": $titleText")
                    },
                    chapterNumber = chap.toDoubleOrNull() ?: -1.0,
                    scanlator = groups.joinToString().ifBlank { null },
                    read = false,
                    bookmark = false,
                    uploadDate = isoToMillis(c["created_at"]?.jsonPrimitive?.contentOrNull),
                    pageCount = 0,
                )
            }
            page++
        } while (page <= lastPage && page <= MAX_CHAPTER_PAGES)
        return out
    }

    override suspend fun pages(chapterId: String): List<String> {
        val html = fetchWeb("$BASE/$chapterId")
        val data = json.parseToJsonElement(extractEmbeddedJson(html, "sv-data")).jsonObject
        val images = (data["chapter"]?.jsonObject?.get("images") as? JsonArray).orEmpty()
        return images.mapNotNull { it.jsonObject["url"]?.jsonPrimitive?.contentOrNull }
    }

    override suspend fun recentUpdates(): List<RecentUpdate> = emptyList()

    // MARK: - Red (vía WebView para sortear Cloudflare)

    private suspend fun fetchWeb(url: String): String = suspendCancellableCoroutine { cont ->
        val fetcher = SourceRegistry.webFetcher
        if (fetcher == null) {
            cont.resumeWithException(Exception("Comick requiere WebView (no inicializado)"))
            return@suspendCancellableCoroutine
        }
        fetcher.fetch(
            url = url,
            onResult = { if (cont.isActive) cont.resume(it) },
            onError = { if (cont.isActive) cont.resumeWithException(Exception(it)) },
        )
    }

    private fun url(path: String, params: List<Pair<String, String>>): String {
        if (params.isEmpty()) return "$BASE$path"
        val q = params.joinToString("&") { (k, v) -> "${k.encodeURLQueryComponent()}=${v.encodeURLQueryComponent()}" }
        return "$BASE$path?$q"
    }

    /** Valida que la respuesta sea JSON; si vino HTML, casi siempre es un reto de Cloudflare. */
    private fun ensureJson(body: String): String {
        val trimmed = body.trimStart()
        if (trimmed.startsWith("<")) {
            val cloudflare = trimmed.contains("Just a moment", ignoreCase = true) ||
                trimmed.contains("challenge", ignoreCase = true) ||
                trimmed.contains("Enable JavaScript", ignoreCase = true)
            throw Exception(
                if (cloudflare) "Comick: Cloudflare aún no resuelto. Reintenta en unos segundos."
                else "Comick devolvió HTML en lugar de JSON (posible cambio de dominio).",
            )
        }
        return body
    }

    // MARK: - Helpers

    /** Extrae el JSON incrustado en `<script id="...">JSON</script>` (Next.js). */
    private fun extractEmbeddedJson(html: String, elementId: String): String {
        val marker = "id=\"$elementId\""
        val start = html.indexOf(marker)
        if (start < 0) throw Exception("Comick: no se encontró #$elementId (¿bloqueo de Cloudflare?)")
        val open = html.indexOf('>', start)
        val close = html.indexOf("</script>", open)
        if (open < 0 || close < 0) throw Exception("Comick: #$elementId mal formado")
        return html.substring(open + 1, close)
    }

    private fun JsonObject.toBrowseManga(): BrowseManga = BrowseManga(
        sourceId = id,
        id = this["slug"]?.jsonPrimitive?.contentOrNull ?: "",
        title = this["title"]?.jsonPrimitive?.contentOrNull ?: "Sin título",
        thumbnailUrl = this["default_thumbnail"]?.jsonPrimitive?.contentOrNull,
        inLibrary = false,
    )

    private fun List<JsonElement>.names(): String? =
        mapNotNull { it.jsonObject["name"]?.jsonPrimitive?.contentOrNull }
            .joinToString().ifBlank { null }

    private fun statusFor(status: Int?): String = when (status) {
        1 -> "ONGOING"
        2 -> "COMPLETED"
        3 -> "CANCELLED"
        4 -> "ON_HIATUS"
        else -> "UNKNOWN"
    }

    /** ISO-8601 (YYYY-MM-DD…) → epoch millis (granularidad de día). Sin dependencias. */
    private fun isoToMillis(iso: String?): Long {
        if (iso == null || iso.length < 10) return 0
        val y = iso.substring(0, 4).toIntOrNull() ?: return 0
        val mo = iso.substring(5, 7).toIntOrNull() ?: return 0
        val d = iso.substring(8, 10).toIntOrNull() ?: return 0
        val yy = if (mo <= 2) y - 1 else y
        val era = (if (yy >= 0) yy else yy - 399) / 400
        val yoe = yy - era * 400
        val doy = (153 * (if (mo > 2) mo - 3 else mo + 9) + 2) / 5 + d - 1
        val doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        val days = era.toLong() * 146097 + doe - 719468
        return days * 86_400_000L
    }

    companion object {
        private const val BASE = "https://comick.live"
        private const val MAX_CHAPTER_PAGES = 20
    }
}
