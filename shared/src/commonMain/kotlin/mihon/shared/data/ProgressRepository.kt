package mihon.shared.data

import mihon.shared.database.MihonDatabase

/** Progreso de lectura por CAPÍTULO (última página + leído), en SQLite local. */
class ProgressRepository(private val database: MihonDatabase) {

    /** Mapa chapterId → progreso, para todo un manga (para la lista de capítulos). */
    fun forManga(sourceId: String, mangaId: String): Map<String, ChapterProgress> =
        database.chapter_progressQueries.forManga(sourceId, mangaId).executeAsList().associate {
            it.chapter_id to ChapterProgress(it.chapter_id, it.last_page.toInt(), it.read)
        }

    /** Capítulo leído/abierto más recientemente (para "continuar"). */
    fun lastRead(sourceId: String, mangaId: String): String? =
        database.chapter_progressQueries.lastRead(sourceId, mangaId).executeAsOneOrNull()

    fun forChapter(sourceId: String, mangaId: String, chapterId: String): ChapterProgress? =
        database.chapter_progressQueries.forChapter(sourceId, mangaId, chapterId).executeAsOneOrNull()?.let {
            ChapterProgress(it.chapter_id, it.last_page.toInt(), it.read)
        }

    fun save(
        sourceId: String,
        mangaId: String,
        chapterId: String,
        lastPage: Int,
        read: Boolean,
        now: Long,
    ) {
        database.chapter_progressQueries.upsert(sourceId, mangaId, chapterId, lastPage.toLong(), read, now)
    }

    /** Borra el progreso de un capítulo (marcar como NO visto). */
    fun clear(sourceId: String, mangaId: String, chapterId: String) {
        database.chapter_progressQueries.clear(sourceId, mangaId, chapterId)
    }

    /** Borra TODO el progreso de un manga (al eliminarlo por completo). */
    fun clearForManga(sourceId: String, mangaId: String) {
        database.chapter_progressQueries.clearForManga(sourceId, mangaId)
    }
}

/** Progreso de un capítulo. */
data class ChapterProgress(
    val chapterId: String,
    val lastPage: Int,
    val read: Boolean,
)
