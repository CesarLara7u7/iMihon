package mihon.shared

import mihon.shared.data.MangaCategory
import mihon.shared.data.CategoryRepository
import mihon.shared.data.DownloadEntry
import mihon.shared.data.DownloadsRepository
import mihon.shared.data.DatabaseLibraryRepository
import mihon.shared.data.FavoritesRepository
import mihon.shared.data.ChapterProgress
import mihon.shared.data.HistoryEntry
import mihon.shared.data.HistoryRepository
import mihon.shared.data.NsfwRepository
import mihon.shared.data.ProgressRepository
import mihon.shared.data.ReadingPrefs
import mihon.shared.data.ReadingPrefsRepository
import mihon.shared.data.ReadingTimeRepository
import mihon.shared.data.SampleLibraryRepository
import mihon.shared.data.Shelf
import mihon.shared.database.createMihonDatabase
import mihon.shared.domain.model.Chapter
import mihon.shared.domain.model.Manga
import mihon.shared.domain.repository.LibraryRepository
import mihon.shared.source.BrowseManga
import mihon.shared.source.MangaSource
import mihon.shared.source.RecentUpdate
import mihon.shared.source.SearchGroup
import mihon.shared.source.SourceChapter
import mihon.shared.source.SourceGenre
import mihon.shared.source.SourceInfo
import mihon.shared.source.SourceMangaDetail
import mihon.shared.source.SourceRegistry
import mihon.shared.source.WebFetcher
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit

/**
 * Punto de entrada del módulo compartido para Swift.
 *
 * Arquitectura SIN servidor: la app consulta las fuentes (MangaDex, etc.) directamente
 * a través de [SourceRegistry]/[MangaSource]. La biblioteca es local ([FavoritesRepository]).
 */
class MihonShared {
    private val database = createMihonDatabase()
    private val sampleLibrary: LibraryRepository = DatabaseLibraryRepository(database)
    private val favorites = FavoritesRepository(database)
    private val progress = ProgressRepository(database)
    private val history = HistoryRepository(database)
    private val readingPrefsRepo = ReadingPrefsRepository(database)
    private val categoriesRepo = CategoryRepository(database)
    private val downloadsRepo = DownloadsRepository(database)
    private val readingTimeRepo = ReadingTimeRepository(database)
    private val nsfwRepo = NsfwRepository(database)

    fun platform(): String = platformName()

    // ───────────────────────── Fuentes (genérico, sin servidor) ─────────────────────────

    /** Fuentes disponibles para que el usuario elija. */
    fun sources(): List<SourceInfo> = SourceRegistry.infos()

    /** Fija el fetcher vía WebView (lo provee Swift) para fuentes tras Cloudflare (Comick). */
    fun setWebFetcher(fetcher: WebFetcher) { SourceRegistry.webFetcher = fetcher }

    // NOTA: toda función suspend llamada desde Swift DEBE anotarse @Throws; si no, una
    // excepción (p. ej. fallo de red) aborta la app en vez de propagarse al catch de Swift.

    @Throws(Exception::class)
    suspend fun popular(sourceId: String, page: Int): List<BrowseManga> =
        enrich(source(sourceId).popular(page))

    @Throws(Exception::class)
    suspend fun search(sourceId: String, query: String): List<BrowseManga> =
        enrich(source(sourceId).search(query, page = 1))

    /** Catálogo con orden (0 popular,1 actualizados,2 mejor puntuados) y filtro de géneros. */
    @Throws(Exception::class)
    suspend fun browse(sourceId: String, sort: Int, genreIds: List<String>, page: Int): List<BrowseManga> =
        enrich(source(sourceId).browse(sort, genreIds, page))

    /** Géneros de una fuente (para los filtros de Explorar). */
    @Throws(Exception::class)
    suspend fun sourceGenres(sourceId: String): List<SourceGenre> = source(sourceId).genres()

    /**
     * Búsqueda GLOBAL: busca en todas las fuentes en paralelo (limitado para respetar límites de
     * tasa) y agrupa por fuente; omite las fuentes sin resultados.
     */
    @Throws(Exception::class)
    suspend fun searchAll(query: String, sourceIds: List<String>): List<SearchGroup> = coroutineScope {
        val sem = Semaphore(4)
        val targets = if (sourceIds.isEmpty()) SourceRegistry.sources
                      else SourceRegistry.sources.filter { it.id in sourceIds }
        targets.map { src ->
            async {
                val results = sem.withPermit {
                    runCatching { src.search(query, 1) }.getOrDefault(emptyList())
                }
                SearchGroup(src.id, src.name, src.lang,
                    results.map { it.copy(inLibrary = favorites.isFavorite(it.sourceId, it.id)) })
            }
        }.awaitAll().filter { it.manga.isNotEmpty() }
    }

    /**
     * Busca en UNA sola fuente. Para búsqueda global en streaming: Swift lanza una llamada por
     * fuente y muestra cada grupo en cuanto llega (sin esperar a todas). Devuelve null si no hay
     * resultados o si la fuente es desconocida/falla.
     */
    @Throws(Exception::class)
    suspend fun searchSource(sourceId: String, query: String): SearchGroup? {
        val src = SourceRegistry.get(sourceId) ?: return null
        val results = runCatching { src.search(query, 1) }.getOrDefault(emptyList())
        if (results.isEmpty()) return null
        return SearchGroup(src.id, src.name, src.lang,
            results.map { it.copy(inLibrary = favorites.isFavorite(it.sourceId, it.id)) })
    }

    // ───────────────────────── Marca +18 por manga ─────────────────────────

    /** Marca/desmarca un manga como +18 (excluido de Historial y Recientes). */
    @Throws(Exception::class)
    fun setMangaNsfw(sourceId: String, mangaId: String, nsfw: Boolean) =
        nsfwRepo.set(sourceId, mangaId, nsfw)

    @Throws(Exception::class)
    fun isMangaNsfw(sourceId: String, mangaId: String): Boolean =
        nsfwRepo.isNsfw(sourceId, mangaId)

    /** Marca un capítulo como visto (read=true) o NO visto (borra su progreso). */
    @Throws(Exception::class)
    fun setChapterRead(sourceId: String, mangaId: String, chapterId: String, read: Boolean, now: Long) {
        if (read) progress.save(sourceId, mangaId, chapterId, 0, true, now)
        else progress.clear(sourceId, mangaId, chapterId)
    }

    /** Elimina por COMPLETO todo rastro del manga: biblioteca, categorías, historial, tiempo de
     *  lectura (tendencias), progreso de capítulos, preferencias y marca +18. (Las descargas las
     *  borra el lado Swift, que también borra los archivos.) */
    @Throws(Exception::class)
    fun purgeManga(sourceId: String, mangaId: String, now: Long) {
        favorites.setFavorite(sourceId, mangaId, "", null, false, now)
        categoriesRepo.clearForManga(sourceId, mangaId)
        history.deleteForManga(sourceId, mangaId)
        readingTimeRepo.deleteForManga(sourceId, mangaId)
        progress.clearForManga(sourceId, mangaId)
        readingPrefsRepo.deleteForManga(sourceId, mangaId)
        nsfwRepo.set(sourceId, mangaId, false)
    }

    @Throws(Exception::class)
    suspend fun mangaDetail(sourceId: String, mangaId: String): SourceMangaDetail {
        val detail = source(sourceId).detail(mangaId)
        return detail.copy(inLibrary = favorites.isFavorite(sourceId, mangaId))
    }

    @Throws(Exception::class)
    suspend fun sourceChapters(sourceId: String, mangaId: String): List<SourceChapter> {
        val chapters = source(sourceId).chapters(mangaId)
        val progressByChapter = progress.forManga(sourceId, mangaId)
        return chapters.map { ch ->
            val p = progressByChapter[ch.id] ?: return@map ch
            ch.copy(read = p.read, lastPage = p.lastPage)
        }
    }

    @Throws(Exception::class)
    suspend fun chapterPages(sourceId: String, chapterId: String): List<String> =
        source(sourceId).pages(chapterId)

    // ───────────────────────── Biblioteca local (favoritos) ─────────────────────────

    @Throws(Exception::class)
    fun libraryManga(): List<BrowseManga> = favorites.library()

    @Throws(Exception::class)
    fun isFavorite(sourceId: String, mangaId: String): Boolean =
        favorites.isFavorite(sourceId, mangaId)

    @Throws(Exception::class)
    fun setFavorite(
        sourceId: String,
        mangaId: String,
        title: String,
        thumbnailUrl: String?,
        favorite: Boolean,
        now: Long,
    ) {
        favorites.setFavorite(sourceId, mangaId, title, thumbnailUrl, favorite, now)
        // Al quitarlo de la biblioteca, también se desvincula de todas sus categorías.
        if (!favorite) categoriesRepo.clearForManga(sourceId, mangaId)
    }

    // ───────────────────────── Categorías / estanterías ─────────────────────────

    @Throws(Exception::class)
    fun categories(): List<MangaCategory> = categoriesRepo.all()

    @Throws(Exception::class)
    fun createCategory(name: String) = categoriesRepo.create(name)

    @Throws(Exception::class)
    fun renameCategory(id: Int, name: String) = categoriesRepo.rename(id, name)

    /** Palabra mágica de una categoría (vacía = pública/visible). */
    @Throws(Exception::class)
    fun setCategoryMagicWord(id: Int, word: String) = categoriesRepo.setMagicWord(id, word)

    /** Estantería privada cuya palabra mágica coincide con `word`, o null. */
    @Throws(Exception::class)
    fun privateShelf(word: String): Shelf? = categoriesRepo.privateShelf(word)

    /** Todas las estanterías privadas (desbloqueo con Face ID). */
    @Throws(Exception::class)
    fun privateShelves(): List<Shelf> = categoriesRepo.privateShelves()

    /** Claves "source|manga" ocultas (solo en categorías privadas), para filtrar el buscador. */
    @Throws(Exception::class)
    fun hiddenLibraryKeys(): List<String> = categoriesRepo.hiddenKeys()

    @Throws(Exception::class)
    fun deleteCategory(id: Int) = categoriesRepo.delete(id)

    /** Categorías a las que pertenece un manga (para marcar casillas en el selector). */
    @Throws(Exception::class)
    fun categoriesForManga(sourceId: String, mangaId: String): List<MangaCategory> =
        categoriesRepo.forManga(sourceId, mangaId)

    @Throws(Exception::class)
    fun setMangaCategory(sourceId: String, mangaId: String, categoryId: Int, inCategory: Boolean) =
        categoriesRepo.setLink(sourceId, mangaId, categoryId, inCategory)

    /** Estanterías de la biblioteca (una por categoría con contenido + "Sin categoría"). */
    @Throws(Exception::class)
    fun libraryShelves(): List<Shelf> = categoriesRepo.shelves()

    // ───────────────────────── Descargas ─────────────────────────

    @Throws(Exception::class)
    fun downloads(): List<DownloadEntry> = downloadsRepo.all()

    @Throws(Exception::class)
    fun downloadsForManga(sourceId: String, mangaId: String): List<DownloadEntry> =
        downloadsRepo.forManga(sourceId, mangaId)

    @Throws(Exception::class)
    fun downloadEntry(sourceId: String, mangaId: String, chapterId: String): DownloadEntry? =
        downloadsRepo.chapter(sourceId, mangaId, chapterId)

    /** Registra/actualiza una descarga (metadatos + estado). */
    @Throws(Exception::class)
    fun upsertDownload(
        sourceId: String, mangaId: String, chapterId: String, mangaTitle: String,
        thumbnailUrl: String?, chapterName: String, totalPages: Int, downloadedPages: Int,
        status: Int, createdAt: Long,
    ) = downloadsRepo.upsert(DownloadEntry(sourceId, mangaId, chapterId, mangaTitle, thumbnailUrl,
        chapterName, totalPages, downloadedPages, status, createdAt))

    @Throws(Exception::class)
    fun updateDownloadProgress(
        sourceId: String, mangaId: String, chapterId: String,
        totalPages: Int, downloadedPages: Int, status: Int,
    ) = downloadsRepo.updateProgress(sourceId, mangaId, chapterId, totalPages, downloadedPages, status)

    @Throws(Exception::class)
    fun deleteDownload(sourceId: String, mangaId: String, chapterId: String) =
        downloadsRepo.deleteChapter(sourceId, mangaId, chapterId)

    @Throws(Exception::class)
    fun deleteDownloadsForManga(sourceId: String, mangaId: String) =
        downloadsRepo.deleteForManga(sourceId, mangaId)

    /** Descargas completadas antes de `cutoff` (para aplicar retención: borrar archivos). */
    @Throws(Exception::class)
    fun downloadsCompletedBefore(cutoff: Long): List<DownloadEntry> =
        downloadsRepo.completedBefore(cutoff)

    @Throws(Exception::class)
    fun deleteDownloadsCompletedBefore(cutoff: Long) = downloadsRepo.deleteCompletedBefore(cutoff)

    // ───────────────────────── Tiempo de lectura / Tendencia ─────────────────────────

    @Throws(Exception::class)
    fun addReadingTime(sourceId: String, mangaId: String, mangaTitle: String,
                       thumbnailUrl: String?, seconds: Int, now: Long) =
        readingTimeRepo.add(sourceId, mangaId, mangaTitle, thumbnailUrl, seconds, now)

    /** Manga en tendencia (más tiempo de lectura desde `cutoff`); excluye los de categorías privadas. */
    @Throws(Exception::class)
    fun trendingManga(cutoff: Long, limit: Int): List<BrowseManga> {
        val hidden = categoriesRepo.privateMangaKeys()
        return readingTimeRepo.trending(cutoff, limit)
            .filter { "${it.sourceId}|${it.id}" !in hidden }
            .map { it.copy(inLibrary = favorites.isFavorite(it.sourceId, it.id)) }
    }

    // ───────────────────────── Progreso de lectura ─────────────────────────

    /** Progreso de un capítulo (para reanudar en el lector). */
    @Throws(Exception::class)
    fun chapterProgress(sourceId: String, mangaId: String, chapterId: String): ChapterProgress? =
        progress.forChapter(sourceId, mangaId, chapterId)

    /** Mapa chapterId → progreso de todo el manga (para refrescar la lista al salir del lector). */
    @Throws(Exception::class)
    fun chaptersProgress(sourceId: String, mangaId: String): Map<String, ChapterProgress> =
        progress.forManga(sourceId, mangaId)

    /** Id del capítulo en curso / más reciente (para el botón "continuar"). */
    @Throws(Exception::class)
    fun lastReadChapter(sourceId: String, mangaId: String): String? =
        progress.lastRead(sourceId, mangaId)

    @Throws(Exception::class)
    fun saveChapterProgress(
        sourceId: String,
        mangaId: String,
        chapterId: String,
        lastPage: Int,
        read: Boolean,
        now: Long,
    ) = progress.save(sourceId, mangaId, chapterId, lastPage, read, now)

    // ───────────────────────── Recientes (actualizaciones) ─────────────────────────

    /** Actualizaciones recientes de TODAS las fuentes, marcadas con si están en biblioteca. */
    @Throws(Exception::class)
    suspend fun recentUpdates(preferredSourceId: String): List<RecentUpdate> {
        val hidden = categoriesRepo.privateMangaKeys() + nsfwRepo.keys()
        // Si hay fuente predeterminada, solo sus actualizaciones; si no, todas.
        val targets = SourceRegistry.get(preferredSourceId)?.let { listOf(it) } ?: SourceRegistry.sources
        return targets
            .flatMap { runCatching { it.recentUpdates() }.getOrDefault(emptyList()) }
            .map { it.copy(inLibrary = favorites.isFavorite(it.sourceId, it.mangaId)) }
            .filter { "${it.sourceId}|${it.mangaId}" !in hidden }
            .sortedByDescending { it.uploadDate }
    }

    // ───────────────────────── Historial ─────────────────────────

    @Throws(Exception::class)
    fun history(): List<HistoryEntry> {
        val hidden = categoriesRepo.privateMangaKeys() + nsfwRepo.keys()
        return history.all().filter { "${it.sourceId}|${it.mangaId}" !in hidden }
    }

    @Throws(Exception::class)
    fun recordHistory(
        sourceId: String,
        mangaId: String,
        mangaTitle: String,
        thumbnailUrl: String?,
        chapterId: String,
        chapterName: String,
        now: Long,
    ) = history.record(sourceId, mangaId, mangaTitle, thumbnailUrl, chapterId, chapterName, now)

    // ───────────────────────── Preferencias de lectura ─────────────────────────

    @Throws(Exception::class)
    fun readingPrefs(sourceId: String, mangaId: String): ReadingPrefs? =
        readingPrefsRepo.get(sourceId, mangaId)

    @Throws(Exception::class)
    fun saveReadingPrefs(
        sourceId: String,
        mangaId: String,
        colorFilter: Int,
        intensity: Double,
        direction: Int,
        mode: Int,
        doublePage: Int,
    ) = readingPrefsRepo.save(sourceId, mangaId, ReadingPrefs(colorFilter, intensity, direction, mode, doublePage))

    private fun source(id: String): MangaSource =
        SourceRegistry.get(id) ?: throw IllegalArgumentException("Fuente desconocida: $id")

    /** Marca inLibrary según los favoritos locales. */
    private fun enrich(list: List<BrowseManga>): List<BrowseManga> =
        list.map { it.copy(inLibrary = favorites.isFavorite(it.sourceId, it.id)) }

    // ───────────────────────── Datos de muestra (Recientes/Historial, provisional) ─────────────────────────

    fun library(): List<Manga> = sampleLibrary.getLibrary()

    fun chapters(mangaId: Long): List<Chapter> = sampleLibrary.getChapters(mangaId)

    fun sourceName(sourceId: Long): String = when (sourceId) {
        SampleLibraryRepository.MANGADEX -> "MangaDex"
        SampleLibraryRepository.COMICK -> "ComicK"
        SampleLibraryRepository.LOCAL -> "Local"
        else -> "Desconocida"
    }

    fun statusLabel(status: Long): String = when (status) {
        Manga.ONGOING -> "En emisión"
        Manga.COMPLETED -> "Completado"
        Manga.LICENSED -> "Licenciado"
        Manga.PUBLISHING_FINISHED -> "Publicación finalizada"
        Manga.CANCELLED -> "Cancelado"
        Manga.ON_HIATUS -> "En pausa"
        else -> "Desconocido"
    }

    fun unreadCount(mangaId: Long): Int = chapters(mangaId).count { !it.read }
}
