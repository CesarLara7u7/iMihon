package mihon.shared.database

import mihon.shared.data.SampleLibraryRepository

/**
 * Siembra la BD con datos de ejemplo si está vacía. La "semilla" es el
 * [SampleLibraryRepository] de la Fase 1, así hay una única fuente de datos de muestra.
 */
internal object DatabaseSeeder {
    fun seedIfEmpty(db: MihonDatabase) {
        if (db.mangasQueries.countMangas().executeAsOne() > 0) return

        val sample = SampleLibraryRepository()
        db.transaction {
            sample.getLibrary().forEach { m ->
                db.mangasQueries.insertManga(
                    m.id, m.source, m.url, m.artist, m.author, m.description, m.genre,
                    m.title, m.status, m.thumbnailUrl, m.favorite, m.initialized,
                    m.viewerFlags, m.chapterFlags, m.coverLastModified, m.dateAdded, m.updateStrategy,
                )
                sample.getChapters(m.id).forEach { c ->
                    db.chaptersQueries.insertChapter(
                        c.id, c.mangaId, c.url, c.name, c.scanlator, c.read, c.bookmark,
                        c.lastPageRead, c.chapterNumber, c.sourceOrder, c.dateFetch, c.dateUpload,
                    )
                }
            }
        }
    }
}
