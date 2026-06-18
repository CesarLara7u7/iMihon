package mihon.shared.data

import mihon.shared.database.MihonDatabase

/** Historial de lectura local (un registro por manga, el más reciente arriba). */
class HistoryRepository(private val database: MihonDatabase) {

    fun all(): List<HistoryEntry> =
        database.historyQueries.getHistory().executeAsList().map {
            HistoryEntry(
                sourceId = it.source_id,
                mangaId = it.manga_id,
                mangaTitle = it.manga_title,
                thumbnailUrl = it.thumbnail_url,
                chapterId = it.chapter_id,
                chapterName = it.chapter_name,
                readAt = it.read_at,
            )
        }

    fun record(
        sourceId: String,
        mangaId: String,
        mangaTitle: String,
        thumbnailUrl: String?,
        chapterId: String,
        chapterName: String,
        readAt: Long,
    ) {
        database.historyQueries.upsertHistory(
            sourceId, mangaId, mangaTitle, thumbnailUrl, chapterId, chapterName, readAt,
        )
    }

    /** Borra el historial de un manga (al quitarlo de la biblioteca). */
    fun deleteForManga(sourceId: String, mangaId: String) {
        database.historyQueries.deleteForManga(sourceId, mangaId)
    }
}

/** Entrada del historial. */
data class HistoryEntry(
    val sourceId: String,
    val mangaId: String,
    val mangaTitle: String,
    val thumbnailUrl: String?,
    val chapterId: String,
    val chapterName: String,
    val readAt: Long,
)
