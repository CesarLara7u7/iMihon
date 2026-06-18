package mihon.shared.source

/**
 * Puente para hacer peticiones a través de un **navegador real** (WKWebView en iOS).
 *
 * Necesario para fuentes tras Cloudflare (Comick, MangaFire): la pila TLS nativa recibe un reto
 * JS ("Just a moment") que solo un motor de navegador puede resolver. Swift lo implementa con un
 * WKWebView oculto que resuelve el reto y ejecuta `fetch()` en el contexto de la página.
 *
 * Estilo *callback* (no `suspend`) a propósito: simplifica que Swift conforme la interfaz Kotlin.
 */
interface WebFetcher {
    /** Descarga el cuerpo de [url] como texto. Llama [onResult] con el cuerpo u [onError] con el mensaje. */
    fun fetch(url: String, onResult: (String) -> Unit, onError: (String) -> Unit)

    /**
     * Carga [pageUrl] en el WebView, ejecuta [triggerJs] (puede ser ""), y CAPTURA la primera
     * petición fetch/XHR del propio sitio cuya URL contenga [urlContains], devolviéndola completa
     * (con tokens firmados, p. ej. el `vrf` de MangaFire). Llama [onError] si no aparece a tiempo.
     */
    fun capture(
        pageUrl: String,
        triggerJs: String,
        urlContains: String,
        onResult: (String) -> Unit,
        onError: (String) -> Unit,
    )
}
