package mihon.shared.data

import mihon.shared.domain.model.Chapter
import mihon.shared.domain.model.Manga
import mihon.shared.domain.model.UpdateStrategy
import mihon.shared.domain.repository.LibraryRepository

/**
 * Implementación de ejemplo (en memoria). Sustituye temporalmente a la BD real.
 * Ahora la "fuente de verdad" de los datos vive en Kotlin compartido, no en Swift.
 * En la Fase 2 se reemplaza por una implementación respaldada por SQLDelight.
 */
class SampleLibraryRepository : LibraryRepository {

    private data class Seed(val total: Int, val unread: Int)

    private val seeds: Map<Long, Seed> = mapOf(
        1L to Seed(30, 3),
        2L to Seed(110, 12),
        3L to Seed(60, 0),
        4L to Seed(45, 5),
        5L to Seed(37, 0),
        6L to Seed(50, 1),
    )

    private val mangas = listOf(
        sample(1, MANGADEX, "Berserk", "Kentaro Miura", Manga.ON_HIATUS,
            listOf("Acción", "Fantasía oscura", "Seinen"),
            "Guts, un espadachín solitario, busca venganza en un mundo plagado de demonios."),
        sample(2, COMICK, "One Piece", "Eiichiro Oda", Manga.ONGOING,
            listOf("Aventura", "Acción", "Comedia"),
            "Monkey D. Luffy y su tripulación buscan el tesoro definitivo: el One Piece."),
        sample(3, MANGADEX, "Vinland Saga", "Makoto Yukimura", Manga.ONGOING,
            listOf("Acción", "Aventura", "Histórico"),
            "La saga de Thorfinn entre vikingos, venganza y redención."),
        sample(4, COMICK, "Chainsaw Man", "Tatsuki Fujimoto", Manga.ONGOING,
            listOf("Acción", "Sobrenatural", "Shōnen"),
            "Denji se fusiona con su demonio mascota para convertirse en Chainsaw Man."),
        sample(5, MANGADEX, "Vagabond", "Takehiko Inoue", Manga.ON_HIATUS,
            listOf("Acción", "Histórico", "Seinen"),
            "La vida del legendario espadachín Miyamoto Musashi."),
        sample(6, LOCAL, "Solo Leveling", "Chugong", Manga.COMPLETED,
            listOf("Acción", "Fantasía", "Aventura"),
            "El cazador más débil de la humanidad obtiene el poder de subir de nivel sin límite."),
    )

    override fun getLibrary(): List<Manga> = mangas

    override fun getChapters(mangaId: Long): List<Chapter> {
        val seed = seeds[mangaId] ?: return emptyList()
        return (seed.total downTo 1).map { n ->
            Chapter.create().copy(
                id = mangaId * 1000 + n,
                mangaId = mangaId,
                name = "Capítulo $n",
                chapterNumber = n.toDouble(),
                read = n <= (seed.total - seed.unread),
                bookmark = n == seed.total,
                scanlator = if (n % 2 == 0) "Scanlation Group" else null,
                dateUpload = 1_700_000_000_000L - n * 86_400_000L,
                sourceOrder = (seed.total - n).toLong(),
            )
        }
    }

    private fun sample(
        id: Long, source: Long, title: String, author: String, status: Long,
        genre: List<String>, description: String,
    ): Manga = Manga(
        id = id, source = source, favorite = true,
        lastUpdate = 0, nextUpdate = 0, fetchInterval = 0, dateAdded = 0,
        viewerFlags = 0, chapterFlags = 0, coverLastModified = 0,
        url = "/manga/$id", title = title, artist = author, author = author,
        description = description, genre = genre, status = status,
        thumbnailUrl = null, updateStrategy = UpdateStrategy.ALWAYS_UPDATE,
        initialized = true, lastModifiedAt = 0, favoriteModifiedAt = null,
        version = 1, notes = "",
    )

    companion object {
        const val MANGADEX = 1L
        const val COMICK = 2L
        const val LOCAL = 3L
    }
}
