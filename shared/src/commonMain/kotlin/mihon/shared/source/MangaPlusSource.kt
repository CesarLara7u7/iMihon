package mihon.shared.source

import io.ktor.client.HttpClient
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.defaultRequest
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.statement.bodyAsText
import kotlin.random.Random
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Fuente nativa de **MANGA Plus by SHUEISHA**. Consulta directamente su API oficial
 * (`jumpg-webapi.tokyo-cdn.com`) añadiendo `format=json` para recibir JSON en lugar del
 * protobuf que devuelve por defecto. Catálogo oficial, gratuito y SFW, multi-idioma.
 *
 * Las imágenes de página llegan **cifradas con XOR**: cada página trae una `encryptionKey`
 * (hex). Se anexa esa clave al final de la URL como fragmento `#<clave>`, y la capa de
 * imágenes de Swift (ImageCache/descargas) la detecta y descifra byte a byte.
 *
 * @param lang código de idioma estándar (es, en, fr…) usado por la app.
 * @param internalLang código interno de MangaPlus (esp, eng, fra…) usado en las peticiones.
 * @param languageName valor del enum `language` que devuelve la API (SPANISH, ENGLISH…).
 */
class MangaPlusSource(
    override val lang: String,
    private val internalLang: String,
    private val languageName: String,
) : MangaSource {

    override val id: String = "mangaplus-$lang"
    override val name: String = "MANGA Plus"
    override val supportsRating: Boolean = false

    private val json = Json { ignoreUnknownKeys = true }

    private val http = HttpClient {
        install(HttpTimeout) {
            requestTimeoutMillis = 30_000
            connectTimeoutMillis = 15_000
        }
        defaultRequest {
            header("Origin", BASE_URL)
            header("Referer", "$BASE_URL/")
            header("User-Agent", USER_AGENT)
            header("SESSION-TOKEN", sessionToken)
        }
    }

    /** Directorio en memoria (rankingV2/home/allV2) para paginar y resolver portadas. */
    private var directory: List<JsonObject> = emptyList()
    private val titleCache = mutableMapOf<String, JsonObject>()

    override suspend fun popular(page: Int): List<BrowseManga> = browse(sort = 0, genreIds = emptyList(), page = page)

    override suspend fun browse(sort: Int, genreIds: List<String>, page: Int): List<BrowseManga> {
        if (page == 1) {
            directory = when (sort) {
                1 -> updatedTitles().ifEmpty { rankedTitles() }
                else -> rankedTitles()
            }
            cache(directory)
        }
        return directory.paged(page)
    }

    override suspend fun search(query: String, page: Int): List<BrowseManga> {
        if (page == 1) {
            val all = allTitles().filter { title ->
                val name = title["name"]?.jsonPrimitive?.contentOrNull.orEmpty()
                val author = title["author"]?.jsonPrimitive?.contentOrNull.orEmpty()
                name.contains(query, ignoreCase = true) || author.contains(query, ignoreCase = true)
            }
            cache(all)
            directory = all
        }
        return directory.paged(page)
    }

    override suspend fun detail(mangaId: String): SourceMangaDetail {
        val view = titleDetail(mangaId)
        val title = view["title"]!!.jsonObject
        val overview = view["overview"]?.jsonPrimitive?.contentOrNull.orEmpty()
        val viewingPeriod = view["viewingPeriodDescription"]?.jsonPrimitive?.contentOrNull.orEmpty()
        val nonAppearance = view["nonAppearanceInfo"]?.jsonPrimitive?.contentOrNull.orEmpty()
        return SourceMangaDetail(
            id = mangaId,
            title = title["name"]?.jsonPrimitive?.contentOrNull ?: "Sin título",
            author = title["author"]?.jsonPrimitive?.contentOrNull?.replace(" / ", ", "),
            artist = title["author"]?.jsonPrimitive?.contentOrNull?.replace(" / ", ", "),
            description = listOf(overview, viewingPeriod).filter { it.isNotBlank() }.joinToString("\n\n"),
            genres = genresFor(view),
            status = statusFor(view, nonAppearance),
            thumbnailUrl = view["titleImageUrl"]?.jsonPrimitive?.contentOrNull
                ?: title["portraitImageUrl"]?.jsonPrimitive?.contentOrNull,
            inLibrary = false,
        )
    }

    override suspend fun chapters(mangaId: String): List<SourceChapter> {
        val view = titleDetail(mangaId)
        val groups = (view["chapterListGroup"] as? JsonArray).orEmpty()
        val chapters = groups.flatMap { node ->
            val g = node.jsonObject
            (g["firstChapterList"] as? JsonArray).orEmpty() + (g["lastChapterList"] as? JsonArray).orEmpty()
        }
        return chapters.mapNotNull { node ->
            val c = node.jsonObject
            // Capítulos caducados (sin subtítulo) no son leíbles: se omiten.
            val subTitle = c["subTitle"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
            val rawName = c["name"]?.jsonPrimitive?.contentOrNull.orEmpty()
            val number = rawName.substringAfter("#", "").toDoubleOrNull() ?: -1.0
            SourceChapter(
                id = c["chapterId"]!!.jsonPrimitive.content,
                name = if (subTitle.isNotBlank()) "$rawName · $subTitle" else rawName,
                chapterNumber = number,
                scanlator = "MANGA Plus",
                read = false,
                bookmark = false,
                uploadDate = 1000L * (c["startTimeStamp"]?.jsonPrimitive?.intOrNull ?: 0),
                pageCount = 0,
            )
        }.sortedByDescending { it.chapterNumber }
    }

    override suspend fun pages(chapterId: String): List<String> {
        val url = "$API/manga_viewer?chapter_id=$chapterId&split=yes&img_quality=super_high&format=json"
        val result = success(http.get(url).bodyAsText())
        val pages = (result["mangaViewer"]?.jsonObject?.get("pages") as? JsonArray).orEmpty()
        return pages.mapNotNull { node ->
            val mangaPage = node.jsonObject["mangaPage"]?.jsonObject ?: return@mapNotNull null
            val imageUrl = mangaPage["imageUrl"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
            val key = mangaPage["encryptionKey"]?.jsonPrimitive?.contentOrNull
            if (key.isNullOrEmpty()) imageUrl else "$imageUrl#$key"
        }
    }

    override suspend fun recentUpdates(): List<RecentUpdate> = emptyList()

    // MARK: - Peticiones

    private suspend fun rankedTitles(): List<JsonObject> {
        val url = "$API/title_list/rankingV2?lang=$internalLang&type=hottest&clang=$internalLang&format=json"
        val result = success(http.get(url).bodyAsText())
        val ranked = (result["titleRankingViewV2"]?.jsonObject?.get("rankedTitles") as? JsonArray).orEmpty()
        return ranked.flatMap { (it.jsonObject["titles"] as? JsonArray).orEmpty() }
            .map { it.jsonObject }
            .filter { it.matchesLang() }
    }

    private suspend fun updatedTitles(): List<JsonObject> {
        val url = "$API/home_v4?lang=$internalLang&clang=$internalLang&format=json"
        val result = runCatching { success(http.get(url).bodyAsText()) }.getOrNull() ?: return emptyList()
        val groups = (result["homeViewV3"]?.jsonObject?.get("groups") as? JsonArray).orEmpty()
        return groups.flatMap { g -> (g.jsonObject["titleGroups"] as? JsonArray).orEmpty() }
            .flatMap { tg -> (tg.jsonObject["titles"] as? JsonArray).orEmpty() }
            .mapNotNull { it.jsonObject["title"]?.jsonObject }
            .filter { it.matchesLang() }
            .distinctBy { it["titleId"]?.jsonPrimitive?.intOrNull }
    }

    private suspend fun allTitles(): List<JsonObject> {
        val result = success(http.get("$API/title_list/allV2?format=json").bodyAsText())
        val groups = (result["allTitlesViewV2"]?.jsonObject?.get("AllTitlesGroup") as? JsonArray).orEmpty()
        return groups.flatMap { (it.jsonObject["titles"] as? JsonArray).orEmpty() }
            .map { it.jsonObject }
            .filter { it.matchesLang() }
    }

    private suspend fun titleDetail(titleId: String): JsonObject {
        val result = success(http.get("$API/title_detailV3?title_id=$titleId&format=json").bodyAsText())
        return result["titleDetailView"]!!.jsonObject
    }

    /** Extrae `success` o lanza con el mensaje de error de la API. */
    private fun success(body: String): JsonObject {
        val root = json.parseToJsonElement(body).jsonObject
        root["success"]?.let { return it.jsonObject }
        val popups = (root["error"]?.jsonObject?.get("popups") as? JsonArray).orEmpty()
        val msg = popups.firstOrNull()?.jsonObject?.get("body")?.jsonPrimitive?.contentOrNull
        throw Exception(msg ?: "Error de MANGA Plus")
    }

    // MARK: - Helpers

    private fun List<JsonObject>.paged(page: Int): List<BrowseManga> =
        drop((page - 1) * PAGE_SIZE).take(PAGE_SIZE).map { it.toBrowseManga() }

    private fun cache(titles: List<JsonObject>) {
        titles.forEach { t -> t["titleId"]?.jsonPrimitive?.intOrNull?.let { titleCache[it.toString()] = t } }
    }

    private fun JsonObject.toBrowseManga(): BrowseManga = BrowseManga(
        sourceId = id,
        id = this["titleId"]!!.jsonPrimitive.content,
        title = this["name"]?.jsonPrimitive?.contentOrNull ?: "Sin título",
        thumbnailUrl = this["portraitImageUrl"]?.jsonPrimitive?.contentOrNull,
        inLibrary = false,
    )

    /** La API marca el idioma con un enum; ausente ⇒ inglés. */
    private fun JsonObject.matchesLang(): Boolean =
        (this["language"]?.jsonPrimitive?.contentOrNull ?: "ENGLISH") == languageName

    private fun genresFor(view: JsonObject): List<String> = buildList {
        val magazine = magazineLabel(view["label"]?.jsonObject?.get("label")?.jsonPrimitive?.contentOrNull)
        if (magazine != null) add(magazine)
        when (view["rating"]?.jsonPrimitive?.contentOrNull) {
            "ALLAGE" -> add("Todas las edades")
            "TEEN" -> add("Adolescente")
            "TEENPLUS" -> add("Adolescente+")
            "MATURE" -> add("Maduro")
        }
        val chapters = (view["chapterListGroup"] as? JsonArray).orEmpty().flatMap {
            (it.jsonObject["firstChapterList"] as? JsonArray).orEmpty() + (it.jsonObject["lastChapterList"] as? JsonArray).orEmpty()
        }
        if (chapters.isNotEmpty() && chapters.all { it.jsonObject["isVerticalOnly"]?.jsonPrimitive?.booleanOrNull == true }) {
            add("Webtoon")
        }
    }

    private fun statusFor(view: JsonObject, nonAppearance: String): String {
        val schedule = view["titleLabels"]?.jsonObject?.get("releaseSchedule")?.jsonPrimitive?.contentOrNull
        return when {
            schedule == "COMPLETED" || schedule == "DISABLED" ||
                nonAppearance.contains(Regex("completado|complete|completo", RegexOption.IGNORE_CASE)) -> "COMPLETED"
            schedule == "HIATUS" || nonAppearance.contains("on a hiatus", ignoreCase = true) -> "ON_HIATUS"
            else -> "ONGOING"
        }
    }

    private fun magazineLabel(code: String?): String? = when (code) {
        "WSJ" -> "Weekly Shounen Jump"
        "SQ" -> "Jump SQ."
        "VJ" -> "V Jump"
        "GIGA" -> "Shounen Jump GIGA"
        "YJ" -> "Weekly Young Jump"
        "TYJ" -> "Tonari no Young Jump"
        "J_PLUS" -> "Shounen Jump+"
        "CREATORS" -> "MANGA Plus Creators"
        "SKJ" -> "Saikyou Jump"
        "UJ" -> "Ultra Jump"
        "DX" -> "Dash X Comic"
        "MEE" -> "Manga Mee"
        else -> null
    }

    /** SESSION-TOKEN: cualquier UUID válido sirve; uno por instancia es suficiente. */
    private val sessionToken: String by lazy {
        val hex = "0123456789abcdef"
        fun seg(n: Int) = (1..n).joinToString("") { hex[Random.nextInt(16)].toString() }
        "${seg(8)}-${seg(4)}-4${seg(3)}-${seg(4)}-${seg(12)}"
    }

    companion object {
        private const val API = "https://jumpg-webapi.tokyo-cdn.com/api"
        private const val BASE_URL = "https://mangaplus.shueisha.co.jp"
        private const val PAGE_SIZE = 24
        private const val USER_AGENT =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36"
    }
}
