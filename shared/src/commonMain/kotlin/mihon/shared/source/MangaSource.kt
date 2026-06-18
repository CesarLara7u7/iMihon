package mihon.shared.source

/**
 * Contrato genérico de una fuente de manga. Cada fuente (MangaDex, etc.) lo implementa
 * llamando DIRECTAMENTE a su API (sin servidor intermediario). Para añadir una fuente nueva,
 * basta crear otra implementación y registrarla en [SourceRegistry].
 *
 * Reemplaza al cliente Suwayomi: ya no hay backend; la app consulta las fuentes por sí misma.
 */
interface MangaSource {
    val id: String
    val name: String
    val lang: String

    /** Si la fuente tiene puntuación/rating nativo (para ofrecer "Mejor puntuados"). */
    val supportsRating: Boolean get() = false

    /** Si la fuente es de contenido adulto (+18): pide confirmación de edad al activarla. */
    val isNsfw: Boolean get() = false

    suspend fun popular(page: Int): List<BrowseManga>
    suspend fun search(query: String, page: Int): List<BrowseManga>
    suspend fun detail(mangaId: String): SourceMangaDetail
    suspend fun chapters(mangaId: String): List<SourceChapter>
    suspend fun pages(chapterId: String): List<String>

    /** Catálogo con orden (0 popular, 1 actualizados, 2 mejor puntuados) y filtro de géneros. */
    suspend fun browse(sort: Int, genreIds: List<String>, page: Int): List<BrowseManga> = popular(page)

    /** Géneros/temas disponibles en la fuente para filtrar. */
    suspend fun genres(): List<SourceGenre> = emptyList()

    /** Últimas actualizaciones de la fuente (para la pestaña Recientes). */
    suspend fun recentUpdates(): List<RecentUpdate> = emptyList()
}

/** Género/tema de una fuente (para filtrar el catálogo). */
data class SourceGenre(val id: String, val name: String)

/** Resultados de búsqueda agrupados por fuente (búsqueda global). */
data class SearchGroup(
    val sourceId: String,
    val sourceName: String,
    val lang: String,
    val manga: List<BrowseManga>,
)

/** Una actualización reciente: capítulo nuevo de un manga. */
data class RecentUpdate(
    val sourceId: String,
    val mangaId: String,
    val mangaTitle: String,
    val thumbnailUrl: String?,
    val chapterId: String,
    val chapterName: String,
    val uploadDate: Long,
    val inLibrary: Boolean,
)

/** Fuente en el listado de selección, expuesta a Swift. */
data class SourceInfo(
    val id: String,
    val name: String,
    val lang: String,
    val iconUrl: String?,
    val isNsfw: Boolean,
    val supportsRating: Boolean = false,
)

/** Manga del catálogo (explorar/buscar/biblioteca). `id` es el id propio de la fuente. */
data class BrowseManga(
    val sourceId: String,
    val id: String,
    val title: String,
    val thumbnailUrl: String?,
    val inLibrary: Boolean,
)

/** Detalle completo de un manga de una fuente. */
data class SourceMangaDetail(
    val id: String,
    val title: String,
    val author: String?,
    val artist: String?,
    val description: String?,
    val genres: List<String>,
    val status: String,
    val thumbnailUrl: String?,
    val inLibrary: Boolean,
)

/** Capítulo de una fuente. `read`/`lastPage` se rellenan con el progreso local. */
data class SourceChapter(
    val id: String,
    val name: String,
    val chapterNumber: Double,
    val scanlator: String?,
    val read: Boolean,
    val bookmark: Boolean,
    val uploadDate: Long,
    val pageCount: Int,
    val lastPage: Int = 0,
)
