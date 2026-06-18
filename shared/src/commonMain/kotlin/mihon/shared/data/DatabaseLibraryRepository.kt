package mihon.shared.data

import mihon.shared.database.Chapters
import mihon.shared.database.Mangas
import mihon.shared.database.MihonDatabase
import mihon.shared.domain.model.Chapter
import mihon.shared.domain.model.Manga
import mihon.shared.domain.repository.LibraryRepository

/**
 * Implementación real respaldada por SQLDelight (Fase 2). Sustituye a
 * [SampleLibraryRepository], que ahora solo sirve para sembrar la BD.
 */
class DatabaseLibraryRepository(
    private val database: MihonDatabase,
) : LibraryRepository {

    override fun getLibrary(): List<Manga> =
        database.mangasQueries.getLibrary().executeAsList().map(::toDomain)

    override fun getChapters(mangaId: Long): List<Chapter> =
        database.chaptersQueries.getByMangaId(mangaId).executeAsList().map(::toDomain)

    private fun toDomain(m: Mangas): Manga = Manga(
        id = m._id,
        source = m.source,
        favorite = m.favorite,
        lastUpdate = m.last_update ?: 0,
        nextUpdate = m.next_update ?: 0,
        fetchInterval = m.calculate_interval.toInt(),
        dateAdded = m.date_added,
        viewerFlags = m.viewer,
        chapterFlags = m.chapter_flags,
        coverLastModified = m.cover_last_modified,
        url = m.url,
        title = m.title,
        artist = m.artist,
        author = m.author,
        description = m.description,
        genre = m.genre,
        status = m.status,
        thumbnailUrl = m.thumbnail_url,
        updateStrategy = m.update_strategy,
        initialized = m.initialized,
        lastModifiedAt = m.last_modified_at,
        favoriteModifiedAt = m.favorite_modified_at,
        version = m.version,
        notes = m.notes,
    )

    private fun toDomain(c: Chapters): Chapter = Chapter(
        id = c._id,
        mangaId = c.manga_id,
        read = c.read,
        bookmark = c.bookmark,
        lastPageRead = c.last_page_read,
        dateFetch = c.date_fetch,
        sourceOrder = c.source_order,
        url = c.url,
        name = c.name,
        dateUpload = c.date_upload,
        chapterNumber = c.chapter_number,
        scanlator = c.scanlator,
        lastModifiedAt = c.last_modified_at,
        version = c.version,
    )
}
