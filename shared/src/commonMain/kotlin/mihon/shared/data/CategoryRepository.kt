package mihon.shared.data

import mihon.shared.database.MihonDatabase
import mihon.shared.source.BrowseManga

/**
 * Categorías/estanterías de la biblioteca (relación N a N: un manga puede estar en varias).
 * Los datos de portada/título salen de `favorites`; aquí solo se gestionan los vínculos.
 *
 * Una categoría con `magicWord` no vacía es PRIVADA: se oculta de las estanterías y solo se
 * revela escribiendo esa palabra en el buscador.
 */
class CategoryRepository(private val database: MihonDatabase) {

    private val categories get() = database.categoriesQueries
    private val links get() = database.manga_categoriesQueries

    fun all(): List<MangaCategory> =
        categories.getCategories().executeAsList()
            .map { MangaCategory(it.id.toInt(), it.name, it.sort.toInt(), it.magic_word) }

    fun create(name: String) {
        val sort = (all().maxOfOrNull { it.sort } ?: -1) + 1
        categories.insertCategory(name, sort.toLong())
    }

    fun rename(id: Int, name: String) = categories.renameCategory(name, id.toLong())

    /** Define la palabra mágica de una categoría (vacía = pública). */
    fun setMagicWord(id: Int, word: String) = categories.setMagicWord(word.trim(), id.toLong())

    fun delete(id: Int) {
        links.removeLinksForCategory(id.toLong())
        categories.deleteCategory(id.toLong())
    }

    /** Categorías a las que pertenece un manga (para marcar casillas). */
    fun forManga(sourceId: String, mangaId: String): List<MangaCategory> {
        val ids = links.categoryIdsForManga(sourceId, mangaId).executeAsList().map { it.toInt() }.toSet()
        return all().filter { it.id in ids }
    }

    fun setLink(sourceId: String, mangaId: String, categoryId: Int, inCategory: Boolean) {
        if (inCategory) {
            links.addLink(sourceId, mangaId, categoryId.toLong())
        } else {
            links.removeLink(sourceId, mangaId, categoryId.toLong())
        }
    }

    /** Quita todos los vínculos de un manga (al sacarlo de la biblioteca). */
    fun clearForManga(sourceId: String, mangaId: String) =
        links.removeLinksForManga(sourceId, mangaId)

    /**
     * Estanterías PÚBLICAS de la Biblioteca: una por categoría no privada con contenido +
     * "Sin categoría". Las privadas se omiten (solo aparecen con su palabra mágica).
     */
    fun shelves(): List<Shelf> {
        val result = mutableListOf<Shelf>()
        for (cat in all()) {
            if (cat.magicWord.isNotEmpty()) continue   // privada → oculta
            val manga = links.favoritesInCategory(cat.id.toLong()).executeAsList().map { it.toBrowseManga() }
            if (manga.isNotEmpty()) result.add(Shelf(cat.id, cat.name, manga))
        }
        val uncategorized = links.uncategorizedFavorites().executeAsList().map { it.toBrowseManga() }
        if (uncategorized.isNotEmpty()) result.add(Shelf(-1, "Sin categoría", uncategorized))
        return result
    }

    /** Todas las estanterías privadas (para desbloqueo biométrico con Face ID). */
    fun privateShelves(): List<Shelf> {
        val result = mutableListOf<Shelf>()
        for (cat in all()) {
            if (cat.magicWord.isEmpty()) continue
            val manga = links.favoritesInCategory(cat.id.toLong()).executeAsList().map { it.toBrowseManga() }
            if (manga.isNotEmpty()) result.add(Shelf(cat.id, cat.name, manga))
        }
        return result
    }

    /** Estantería de la categoría privada cuya palabra mágica coincide (sin distinción de may/min). */
    fun privateShelf(magicWord: String): Shelf? {
        val word = magicWord.trim()
        if (word.isEmpty()) return null
        val cat = all().firstOrNull { it.magicWord.isNotEmpty() && it.magicWord.equals(word, ignoreCase = true) }
            ?: return null
        val manga = links.favoritesInCategory(cat.id.toLong()).executeAsList().map { it.toBrowseManga() }
        return Shelf(cat.id, cat.name, manga)
    }

    /** Claves "source|manga" de mangas en CUALQUIER categoría privada (para excluir de historial/recientes). */
    fun privateMangaKeys(): Set<String> {
        val privateIds = all().filter { it.magicWord.isNotEmpty() }.map { it.id }.toSet()
        if (privateIds.isEmpty()) return emptySet()
        return links.allLinks().executeAsList()
            .filter { it.category_id.toInt() in privateIds }
            .map { "${it.source_id}|${it.manga_id}" }
            .toSet()
    }

    /**
     * Claves "source|manga" de los mangas que SOLO viven en categorías privadas (sin ninguna
     * pública ni "Sin categoría"). Se excluyen del buscador por título para que no se filtren.
     */
    fun hiddenKeys(): List<String> {
        val privateIds = all().filter { it.magicWord.isNotEmpty() }.map { it.id }.toSet()
        if (privateIds.isEmpty()) return emptyList()
        return links.allLinks().executeAsList()
            .groupBy { it.source_id to it.manga_id }
            .filter { (_, rows) -> rows.all { it.category_id.toInt() in privateIds } }
            .map { "${it.key.first}|${it.key.second}" }
    }
}

private fun mihon.shared.database.FavoritesInCategory.toBrowseManga() =
    BrowseManga(sourceId = source_id, id = manga_id, title = title, thumbnailUrl = thumbnail_url, inLibrary = true)

private fun mihon.shared.database.UncategorizedFavorites.toBrowseManga() =
    BrowseManga(sourceId = source_id, id = manga_id, title = title, thumbnailUrl = thumbnail_url, inLibrary = true)

/** Categoría de la biblioteca. `magicWord` no vacía ⇒ privada. */
data class MangaCategory(val id: Int, val name: String, val sort: Int, val magicWord: String)

/** Estantería: una categoría (o "Sin categoría", id = -1) con su contenido. */
data class Shelf(val categoryId: Int, val name: String, val manga: List<BrowseManga>)
