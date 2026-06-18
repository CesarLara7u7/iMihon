package mihon.shared.data

import mihon.shared.database.MihonDatabase

/** Preferencias de lectura por manga (filtro, intensidad, dirección, modo, páginas dobles) en SQLite. */
class ReadingPrefsRepository(private val database: MihonDatabase) {

    fun get(sourceId: String, mangaId: String): ReadingPrefs? =
        database.reading_prefsQueries.getPrefs(sourceId, mangaId).executeAsOneOrNull()?.let {
            ReadingPrefs(
                colorFilter = it.color_filter.toInt(),
                intensity = it.intensity,
                direction = it.direction.toInt(),
                mode = it.mode.toInt(),
                doublePage = it.double_page.toInt(),
            )
        }

    fun save(sourceId: String, mangaId: String, prefs: ReadingPrefs) {
        database.reading_prefsQueries.upsertPrefs(
            sourceId, mangaId,
            prefs.colorFilter.toLong(), prefs.intensity, prefs.direction.toLong(),
            prefs.mode.toLong(), prefs.doublePage.toLong(),
        )
    }

    fun deleteForManga(sourceId: String, mangaId: String) {
        database.reading_prefsQueries.deleteForManga(sourceId, mangaId)
    }
}

/**
 * Preferencias de lectura. colorFilter: 0 none,1 B/N,2 sepia,3 sepia suave; direction: 0 LTR,1 RTL;
 * mode: 0 paginado,1 webtoon; doublePage: 0 no,1 sí.
 */
data class ReadingPrefs(
    val colorFilter: Int,
    val intensity: Double,
    val direction: Int,
    val mode: Int,
    val doublePage: Int,
)
