package mihon.shared.source

/**
 * Registro de fuentes disponibles. Para añadir una fuente nueva, impleméntala como
 * [MangaSource] y agrégala aquí. La app las lista para que el usuario elija.
 */
object SourceRegistry {

    /** Fetcher vía WebView (lo fija Swift al arrancar). Lo usan fuentes tras Cloudflare (Comick). */
    var webFetcher: WebFetcher? = null

    /** Idiomas de MangaDex que se ofrecen (cada uno es una "fuente" mangadex-<lang>). */
    private val mangaDexLanguages = listOf(
        "es", "es-419", "en", "pt-br", "fr", "it", "de", "ru", "id", "ja", "ko", "zh", "ar",
    )

    /** Idiomas de MANGA Plus: (lang app, código interno, enum de idioma de la API). */
    private val mangaPlusLanguages = listOf(
        Triple("en", "eng", "ENGLISH"),
        Triple("es", "esp", "SPANISH"),
        Triple("fr", "fra", "FRENCH"),
        Triple("pt-br", "ptb", "PORTUGUESE_BR"),
        Triple("id", "ind", "INDONESIAN"),
        Triple("ru", "rus", "RUSSIAN"),
        Triple("th", "tha", "THAI"),
        Triple("vi", "vie", "VIETNAMESE"),
        Triple("de", "deu", "GERMAN"),
    )

    /** Idiomas de Comick (su sitio usa códigos simples; el código filtra los capítulos). */
    private val comickLanguages = listOf(
        "en", "es", "pt", "fr", "it", "de", "ru", "id", "ko", "ja", "th", "vi", "ar",
    )

    /** Idiomas de MangaFire: (lang app, langCode del sitio). */
    private val mangaFireLanguages = listOf(
        "en" to "en",
        "es" to "es",
        "es-419" to "es-la",
        "fr" to "fr",
        "ja" to "ja",
        "pt-br" to "pt-br",
    )

    val sources: List<MangaSource> =
        mangaDexLanguages.map { MangaDexSource(lang = it) } +
            mangaPlusLanguages.map { (lang, internal, langName) ->
                MangaPlusSource(lang = lang, internalLang = internal, languageName = langName)
            } +
            comickLanguages.map { ComickSource(lang = it) } +
            mangaFireLanguages.map { (lang, code) -> MangaFireSource(lang = lang, langCode = code) }

    fun get(id: String): MangaSource? = sources.firstOrNull { it.id == id }

    fun infos(): List<SourceInfo> = sources.map {
        SourceInfo(id = it.id, name = it.name, lang = it.lang, iconUrl = null,
                   isNsfw = it.isNsfw, supportsRating = it.supportsRating)
    }
}
