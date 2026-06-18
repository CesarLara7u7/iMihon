package mihon.shared.data

import mihon.shared.database.MihonDatabase
import mihon.shared.source.BrowseManga

/** Tiempo de lectura por manga; alimenta el estante "Tendencia". */
class ReadingTimeRepository(private val database: MihonDatabase) {

    private val queries get() = database.reading_timeQueries

    fun add(sourceId: String, mangaId: String, mangaTitle: String, thumbnailUrl: String?,
            seconds: Int, now: Long) {
        queries.addTime(sourceId, mangaId, mangaTitle, thumbnailUrl, seconds.toLong(), now)
    }

    /** Manga leídos desde `cutoff`, por más tiempo de lectura (tendencia). */
    fun trending(cutoff: Long, limit: Int): List<BrowseManga> =
        queries.trending(cutoff, limit.toLong()).executeAsList().map {
            BrowseManga(sourceId = it.source_id, id = it.manga_id, title = it.manga_title,
                        thumbnailUrl = it.thumbnail_url, inLibrary = false)
        }

    fun deleteForManga(sourceId: String, mangaId: String) {
        queries.deleteForManga(sourceId, mangaId)
    }
}
