package mihon.shared.data

import mihon.shared.database.MihonDatabase

/** Manga marcados como +18 por el usuario; se excluyen de Historial y Recientes. */
class NsfwRepository(private val database: MihonDatabase) {

    private val queries get() = database.nsfw_mangaQueries

    fun set(sourceId: String, mangaId: String, nsfw: Boolean) {
        if (nsfw) queries.mark(sourceId, mangaId) else queries.unmark(sourceId, mangaId)
    }

    fun isNsfw(sourceId: String, mangaId: String): Boolean =
        queries.isNsfw(sourceId, mangaId).executeAsOne() > 0

    /** Claves "source|manga" de todos los marcados +18. */
    fun keys(): Set<String> =
        queries.all().executeAsList().map { "${it.source_id}|${it.manga_id}" }.toSet()
}
