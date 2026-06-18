package mihon.shared.data

import mihon.shared.database.Downloads
import mihon.shared.database.MihonDatabase

/**
 * Metadatos y estado de las descargas (los archivos de página viven en disco, gestionados
 * por la capa Swift). status: 0 en cola, 1 descargando, 2 completado, 3 error.
 */
class DownloadsRepository(private val database: MihonDatabase) {

    private val queries get() = database.downloadsQueries

    fun all(): List<DownloadEntry> = queries.getAll().executeAsList().map { it.toEntry() }

    fun forManga(sourceId: String, mangaId: String): List<DownloadEntry> =
        queries.forManga(sourceId, mangaId).executeAsList().map { it.toEntry() }

    fun chapter(sourceId: String, mangaId: String, chapterId: String): DownloadEntry? =
        queries.getChapter(sourceId, mangaId, chapterId).executeAsOneOrNull()?.toEntry()

    fun upsert(entry: DownloadEntry) = queries.upsert(
        entry.sourceId, entry.mangaId, entry.chapterId, entry.mangaTitle, entry.thumbnailUrl,
        entry.chapterName, entry.totalPages.toLong(), entry.downloadedPages.toLong(),
        entry.status.toLong(), entry.createdAt,
    )

    fun updateProgress(sourceId: String, mangaId: String, chapterId: String,
                       totalPages: Int, downloadedPages: Int, status: Int) =
        queries.updateProgress(totalPages.toLong(), downloadedPages.toLong(), status.toLong(),
            sourceId, mangaId, chapterId)

    fun deleteChapter(sourceId: String, mangaId: String, chapterId: String) =
        queries.deleteChapter(sourceId, mangaId, chapterId)

    fun deleteForManga(sourceId: String, mangaId: String) =
        queries.deleteForManga(sourceId, mangaId)

    fun completedBefore(cutoff: Long): List<DownloadEntry> =
        queries.completedBefore(cutoff).executeAsList().map { it.toEntry() }

    fun deleteCompletedBefore(cutoff: Long) = queries.deleteCompletedBefore(cutoff)
}

private fun Downloads.toEntry() = DownloadEntry(
    sourceId = source_id, mangaId = manga_id, chapterId = chapter_id, mangaTitle = manga_title,
    thumbnailUrl = thumbnail_url, chapterName = chapter_name, totalPages = total_pages.toInt(),
    downloadedPages = downloaded_pages.toInt(), status = status.toInt(), createdAt = created_at,
)

/** Una descarga (capítulo). status: 0 en cola, 1 descargando, 2 completado, 3 error. */
data class DownloadEntry(
    val sourceId: String,
    val mangaId: String,
    val chapterId: String,
    val mangaTitle: String,
    val thumbnailUrl: String?,
    val chapterName: String,
    val totalPages: Int,
    val downloadedPages: Int,
    val status: Int,
    val createdAt: Long,
)
