package mihon.shared.data

import mihon.shared.database.MihonDatabase
import mihon.shared.source.BrowseManga

/** Biblioteca local (favoritos) respaldada por SQLDelight. Reemplaza la biblioteca del servidor. */
class FavoritesRepository(private val database: MihonDatabase) {

    fun library(): List<BrowseManga> =
        database.favoritesQueries.getFavorites().executeAsList().map { row ->
            BrowseManga(
                sourceId = row.source_id,
                id = row.manga_id,
                title = row.title,
                thumbnailUrl = row.thumbnail_url,
                inLibrary = true,
            )
        }

    fun isFavorite(sourceId: String, mangaId: String): Boolean =
        database.favoritesQueries.isFavorite(sourceId, mangaId).executeAsOne() > 0

    fun setFavorite(
        sourceId: String,
        mangaId: String,
        title: String,
        thumbnailUrl: String?,
        favorite: Boolean,
        now: Long,
    ) {
        if (favorite) {
            database.favoritesQueries.addFavorite(sourceId, mangaId, title, thumbnailUrl, now)
        } else {
            database.favoritesQueries.removeFavorite(sourceId, mangaId)
        }
    }
}
