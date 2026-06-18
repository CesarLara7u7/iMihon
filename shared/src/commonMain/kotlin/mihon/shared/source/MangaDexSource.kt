package mihon.shared.source

import io.ktor.client.HttpClient
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.defaultRequest
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpHeaders
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Fuente nativa de **MangaDex**: consulta directamente `api.mangadex.org` (sin servidor).
 * Parametrizable por idioma para registrar variantes (es, en, ...).
 */
class MangaDexSource(override val lang: String) : MangaSource {

    override val id: String = "mangadex-$lang"
    override val name: String = "MangaDex"
    override val supportsRating: Boolean = true

    private val json = Json { ignoreUnknownKeys = true }

    private val http = HttpClient {
        install(HttpTimeout) {
            requestTimeoutMillis = 30_000
            connectTimeoutMillis = 15_000
        }
        defaultRequest {
            header(HttpHeaders.UserAgent, USER_AGENT)
        }
    }

    override suspend fun popular(page: Int): List<BrowseManga> =
        browse(sort = 0, genreIds = emptyList(), page = page)

    override suspend fun search(query: String, page: Int): List<BrowseManga> =
        mangaList(page, query = query, sort = 0, genreIds = emptyList())

    override suspend fun browse(sort: Int, genreIds: List<String>, page: Int): List<BrowseManga> =
        mangaList(page, query = null, sort = sort, genreIds = genreIds)

    override suspend fun genres(): List<SourceGenre> {
        val response = http.get("$API/manga/tag")
        val data = json.parseToJsonElement(response.bodyAsText()).jsonObject["data"]!!.jsonArray
        return data.mapNotNull { node ->
            val o = node.jsonObject
            val attr = o["attributes"]?.jsonObject
            val group = attr?.get("group")?.jsonPrimitive?.contentOrNull
            if (group != "genre" && group != "theme") return@mapNotNull null
            val name = (attr["name"] as? JsonObject)?.localized() ?: return@mapNotNull null
            SourceGenre(id = o["id"]!!.jsonPrimitive.content, name = name)
        }.sortedBy { it.name }
    }

    private suspend fun mangaList(page: Int, query: String?, sort: Int, genreIds: List<String>): List<BrowseManga> {
        val offset = (page - 1) * LIMIT
        val response = http.get("$API/manga") {
            url {
                parameters.append("limit", LIMIT.toString())
                parameters.append("offset", offset.toString())
                if (!query.isNullOrBlank()) {
                    parameters.append("title", query)
                    parameters.append("order[relevance]", "desc")
                } else {
                    when (sort) {
                        1 -> parameters.append("order[latestUploadedChapter]", "desc")
                        2 -> parameters.append("order[rating]", "desc")
                        else -> parameters.append("order[followedCount]", "desc")
                    }
                }
                genreIds.forEach { parameters.append("includedTags[]", it) }
                parameters.append("includes[]", "cover_art")
                parameters.append("availableTranslatedLanguage[]", lang)
                parameters.append("hasAvailableChapters", "true")
                CONTENT_RATINGS.forEach { parameters.append("contentRating[]", it) }
            }
        }
        val data = json.parseToJsonElement(response.bodyAsText()).jsonObject["data"]!!.jsonArray
        return data.map { it.jsonObject.toBrowseManga() }
    }

    override suspend fun detail(mangaId: String): SourceMangaDetail {
        val response = http.get("$API/manga/$mangaId") {
            url {
                parameters.append("includes[]", "cover_art")
                parameters.append("includes[]", "author")
                parameters.append("includes[]", "artist")
            }
        }
        val m = json.parseToJsonElement(response.bodyAsText()).jsonObject["data"]!!.jsonObject
        val attr = m["attributes"]!!.jsonObject
        val rels = m["relationships"]!!.jsonArray
        val genres = (attr["tags"] as? JsonArray).orEmpty()
            .mapNotNull { (it.jsonObject["attributes"]?.jsonObject?.get("name") as? JsonObject)?.localized() }
        return SourceMangaDetail(
            id = m["id"]!!.jsonPrimitive.content,
            title = (attr["title"] as? JsonObject)?.localized() ?: "Sin título",
            author = rels.relName("author"),
            artist = rels.relName("artist"),
            description = (attr["description"] as? JsonObject)?.localized(),
            genres = genres,
            status = mapStatus(attr["status"]?.jsonPrimitive?.contentOrNull),
            thumbnailUrl = coverUrl(m["id"]!!.jsonPrimitive.content, rels),
            inLibrary = false,
        )
    }

    override suspend fun chapters(mangaId: String): List<SourceChapter> {
        val response = http.get("$API/manga/$mangaId/feed") {
            url {
                parameters.append("translatedLanguage[]", lang)
                parameters.append("order[volume]", "desc")
                parameters.append("order[chapter]", "desc")
                parameters.append("limit", "500")
                parameters.append("includes[]", "scanlation_group")
                CONTENT_RATINGS.forEach { parameters.append("contentRating[]", it) }
            }
        }
        val data = json.parseToJsonElement(response.bodyAsText()).jsonObject["data"]!!.jsonArray
        return data.mapNotNull { node ->
            val c = node.jsonObject
            val attr = c["attributes"]!!.jsonObject
            // Saltar capítulos externos (no leíbles: redirigen a la web oficial).
            if (!attr["externalUrl"]?.jsonPrimitive?.contentOrNull.isNullOrBlank()) return@mapNotNull null
            val number = attr["chapter"]?.jsonPrimitive?.contentOrNull?.toDoubleOrNull() ?: -1.0
            val volume = attr["volume"]?.jsonPrimitive?.contentOrNull
            val titleText = attr["title"]?.jsonPrimitive?.contentOrNull
            val name = buildString {
                if (volume != null) append("Vol. $volume ")
                if (number >= 0) append("Cap. ${formatNumber(number)}") else append("Oneshot")
                if (!titleText.isNullOrBlank()) append(" - $titleText")
            }
            SourceChapter(
                id = c["id"]!!.jsonPrimitive.content,
                name = name,
                chapterNumber = number,
                scanlator = c["relationships"]!!.jsonArray.relName("scanlation_group"),
                read = false,
                bookmark = false,
                uploadDate = isoToMillis(attr["readableAt"]?.jsonPrimitive?.contentOrNull),
                pageCount = attr["pages"]?.jsonPrimitive?.intOrNull ?: 0,
            )
        }
    }

    override suspend fun recentUpdates(): List<RecentUpdate> {
        val response = http.get("$API/chapter") {
            url {
                parameters.append("translatedLanguage[]", lang)
                parameters.append("order[readableAt]", "desc")
                parameters.append("limit", "40")
                parameters.append("includes[]", "manga")
                CONTENT_RATINGS.forEach { parameters.append("contentRating[]", it) }
            }
        }
        val data = json.parseToJsonElement(response.bodyAsText()).jsonObject["data"]!!.jsonArray
        val raw = data.mapNotNull { node ->
            val c = node.jsonObject
            val attr = c["attributes"]!!.jsonObject
            if (!attr["externalUrl"]?.jsonPrimitive?.contentOrNull.isNullOrBlank()) return@mapNotNull null
            if ((attr["pages"]?.jsonPrimitive?.intOrNull ?: 0) == 0) return@mapNotNull null
            val mangaRel = c["relationships"]!!.jsonArray
                .firstOrNull { it.jsonObject["type"]?.jsonPrimitive?.contentOrNull == "manga" }?.jsonObject
                ?: return@mapNotNull null
            val mangaId = mangaRel["id"]!!.jsonPrimitive.content
            val mangaTitle = (mangaRel["attributes"]?.jsonObject?.get("title") as? JsonObject)?.localized() ?: "Sin título"
            val number = attr["chapter"]?.jsonPrimitive?.contentOrNull
            RecentUpdate(
                sourceId = id, mangaId = mangaId, mangaTitle = mangaTitle, thumbnailUrl = null,
                chapterId = c["id"]!!.jsonPrimitive.content,
                chapterName = if (number != null) "Cap. ${formatNumber(number.toDoubleOrNull() ?: -1.0)}" else "Oneshot",
                uploadDate = isoToMillis(attr["readableAt"]?.jsonPrimitive?.contentOrNull),
                inLibrary = false,
            )
        }
        val covers = mangaCovers(raw.map { it.mangaId }.distinct())
        return raw.map { it.copy(thumbnailUrl = covers[it.mangaId]) }
    }

    /** Portadas en lote para una lista de manga. */
    private suspend fun mangaCovers(ids: List<String>): Map<String, String> {
        if (ids.isEmpty()) return emptyMap()
        val response = http.get("$API/manga") {
            url {
                ids.take(100).forEach { parameters.append("ids[]", it) }
                parameters.append("includes[]", "cover_art")
                parameters.append("limit", ids.size.coerceAtMost(100).toString())
                CONTENT_RATINGS.forEach { parameters.append("contentRating[]", it) }
            }
        }
        val data = json.parseToJsonElement(response.bodyAsText()).jsonObject["data"]!!.jsonArray
        return data.mapNotNull { node ->
            val m = node.jsonObject
            val mid = m["id"]!!.jsonPrimitive.content
            val url = coverUrl(mid, m["relationships"]!!.jsonArray) ?: return@mapNotNull null
            mid to url
        }.toMap()
    }

    override suspend fun pages(chapterId: String): List<String> {
        val response = http.get("$API/at-home/server/$chapterId")
        val root = json.parseToJsonElement(response.bodyAsText()).jsonObject
        val baseUrl = root["baseUrl"]!!.jsonPrimitive.content
        val chapter = root["chapter"]!!.jsonObject
        val hash = chapter["hash"]!!.jsonPrimitive.content
        return chapter["data"]!!.jsonArray.map { "$baseUrl/data/$hash/${it.jsonPrimitive.content}" }
    }

    // MARK: - helpers

    private fun JsonObject.toBrowseManga(): BrowseManga {
        val attr = this["attributes"]!!.jsonObject
        val mangaId = this["id"]!!.jsonPrimitive.content
        return BrowseManga(
            sourceId = id,
            id = mangaId,
            title = (attr["title"] as? JsonObject)?.localized() ?: "Sin título",
            thumbnailUrl = coverUrl(mangaId, this["relationships"]!!.jsonArray),
            inLibrary = false,
        )
    }

    /** Texto localizado preferentemente en [lang], luego inglés, luego el primero. */
    private fun JsonObject.localized(): String? =
        this[lang]?.jsonPrimitive?.contentOrNull
            ?: this["en"]?.jsonPrimitive?.contentOrNull
            ?: values.firstOrNull()?.jsonPrimitive?.contentOrNull

    private fun JsonArray.relName(type: String): String? =
        firstOrNull { it.jsonObject["type"]?.jsonPrimitive?.contentOrNull == type }
            ?.jsonObject?.get("attributes")?.jsonObject?.get("name")?.jsonPrimitive?.contentOrNull

    private fun coverUrl(mangaId: String, rels: JsonArray): String? {
        val file = rels.firstOrNull { it.jsonObject["type"]?.jsonPrimitive?.contentOrNull == "cover_art" }
            ?.jsonObject?.get("attributes")?.jsonObject?.get("fileName")?.jsonPrimitive?.contentOrNull
            ?: return null
        return "$COVERS/$mangaId/$file.512.jpg"
    }

    private fun mapStatus(status: String?): String = when (status) {
        "ongoing" -> "ONGOING"
        "completed" -> "COMPLETED"
        "hiatus" -> "ON_HIATUS"
        "cancelled" -> "CANCELLED"
        else -> "UNKNOWN"
    }

    private fun formatNumber(n: Double): String =
        if (n % 1.0 == 0.0) n.toLong().toString() else n.toString()

    /** Convierte una fecha ISO-8601 (YYYY-MM-DD...) a epoch millis (granularidad de día). Sin dependencias. */
    private fun isoToMillis(iso: String?): Long {
        if (iso == null || iso.length < 10) return 0
        val y = iso.substring(0, 4).toIntOrNull() ?: return 0
        val mo = iso.substring(5, 7).toIntOrNull() ?: return 0
        val d = iso.substring(8, 10).toIntOrNull() ?: return 0
        // Algoritmo days-from-civil (Howard Hinnant).
        val yy = if (mo <= 2) y - 1 else y
        val era = (if (yy >= 0) yy else yy - 399) / 400
        val yoe = yy - era * 400
        val doy = (153 * (if (mo > 2) mo - 3 else mo + 9) + 2) / 5 + d - 1
        val doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        val days = era.toLong() * 146097 + doe - 719468
        return days * 86_400_000L
    }

    companion object {
        private const val API = "https://api.mangadex.org"
        private const val COVERS = "https://uploads.mangadex.org/covers"
        private const val LIMIT = 30
        private val CONTENT_RATINGS = listOf("safe", "suggestive", "erotica")
        // MangaDex (Cloudflare) ahora RECHAZA User-Agents de navegador (Safari/Chrome → 400 HTML)
        // y acepta UA neutros. Usamos uno propio de la app.
        private const val USER_AGENT = "Mihon/1.0 (iOS; KMP)"
    }
}
