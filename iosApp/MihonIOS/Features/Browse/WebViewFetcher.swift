import WebKit
import Shared

/// Cliente HTTP a través de un `WKWebView` oculto, para fuentes tras **Cloudflare** (Comick,
/// MangaFire). Ejecuta `fetch()` en el contexto de la página (hereda cookies + huella TLS real de
/// WebKit, que sí pasa Cloudflare, al contrario que URLSession).
///
/// Implementa la interfaz Kotlin [WebFetcher]:
/// - `fetch(url)`: descarga el cuerpo de una URL (API/HTML) como texto.
/// - `capture(pageUrl, triggerJs, urlContains)`: carga una página, opcionalmente dispara su JS, y
///   captura la primera petición fetch/XHR que coincide (para tokens firmados como el `vrf` de
///   MangaFire).
///
/// Una sola instancia/WebView compartida; las operaciones se **serializan** (una navegación cambia
/// el estado global). El reto de Cloudflare se resuelve por origen y se reutiliza.
final class WebViewFetcher: NSObject, WebFetcher {
    static let shared = WebViewFetcher()

    private var webView: WKWebView?
    private var readyOrigin: String?        // origen con el reto ya resuelto y página cargada
    private var queue: Task<Void, Never> = Task {}   // cola serial de operaciones

    // MARK: - WebFetcher (Kotlin)

    func fetch(url: String, onResult: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        enqueue({ try await self.doFetch(url) }, onResult, onError)
    }

    func capture(pageUrl: String, triggerJs: String, urlContains: String,
                 onResult: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        enqueue({ try await self.doCapture(pageUrl, triggerJs, urlContains) }, onResult, onError)
    }

    /// Encola la operación tras la anterior (serialización) y entrega por callback.
    private func enqueue(_ work: @escaping () async throws -> String,
                         _ onResult: @escaping (String) -> Void, _ onError: @escaping (String) -> Void) {
        let prev = queue
        queue = Task { @MainActor in
            await prev.value
            do { onResult(try await work()) }
            catch { onError((error as NSError).localizedDescription) }
        }
    }

    // MARK: - Operaciones

    @MainActor
    private func doFetch(_ url: String, allowRetry: Bool = true) async throws -> String {
        let origin = originOf(url)
        try await ensureOrigin(origin)
        let text = try await jsFetch(url)
        if allowRetry, looksLikeChallenge(text) {
            readyOrigin = nil
            try await ensureOrigin(origin)
            return try await jsFetch(url)
        }
        return text
    }

    @MainActor
    private func doCapture(_ pageUrl: String, _ triggerJs: String, _ urlContains: String) async throws -> String {
        let wv = ensureWebView()
        // Carga completa de la página para que su JS corra y dispare las peticiones a capturar.
        wv.load(URLRequest(url: URL(string: pageUrl)!))
        try await waitUntilCleared(wv)
        readyOrigin = originOf(pageUrl)
        _ = try? await wv.callAsyncJavaScript("window.__cap = [];", arguments: [:], in: nil, contentWorld: .page)

        for _ in 0..<18 {
            if !triggerJs.isEmpty {
                _ = try? await wv.callAsyncJavaScript(triggerJs, arguments: [:], in: nil, contentWorld: .page)
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            let hit = try? await wv.callAsyncJavaScript(
                "return (window.__cap || []).find(u => u.includes(p)) || '';",
                arguments: ["p": urlContains], in: nil, contentWorld: .page)
            if let s = hit as? String, !s.isEmpty { return s }
        }
        throw NSError(domain: "Web", code: -2, userInfo: [NSLocalizedDescriptionKey:
            "No se pudo capturar la petición (\(urlContains)). Reintenta en unos segundos."])
    }

    // MARK: - Helpers WebView

    @MainActor
    private func jsFetch(_ url: String) async throws -> String {
        let wv = webView!
        let js = "const r = await fetch(u, { headers: { 'Accept': '*/*' }, credentials: 'include' }); return await r.text();"
        let result = try await wv.callAsyncJavaScript(js, arguments: ["u": url], in: nil, contentWorld: .page)
        return (result as? String) ?? ""
    }

    /// Garantiza que el WebView esté en [origin] con el reto resuelto.
    @MainActor
    private func ensureOrigin(_ origin: String) async throws {
        if readyOrigin == origin { return }
        let wv = ensureWebView()
        wv.load(URLRequest(url: URL(string: "\(origin)/")!))
        try await waitUntilCleared(wv)
        readyOrigin = origin
    }

    /// Espera a que el reto de Cloudflare desaparezca (título real, no "Just a moment").
    @MainActor
    private func waitUntilCleared(_ wv: WKWebView) async throws {
        for _ in 0..<22 {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            let title = (try? await wv.callAsyncJavaScript("return document.title;", arguments: [:], in: nil, contentWorld: .page)) as? String
            if let t = title, !t.isEmpty, !t.contains("Just a moment") { return }
        }
        throw NSError(domain: "Web", code: -1, userInfo: [NSLocalizedDescriptionKey:
            "No se pudo resolver el reto de Cloudflare. Inténtalo de nuevo en unos segundos."])
    }

    private func looksLikeChallenge(_ s: String) -> Bool {
        let head = s.prefix(800)
        return head.contains("Just a moment") || head.contains("challenge-platform") || head.contains("Enable JavaScript")
    }

    private func originOf(_ url: String) -> String {
        guard let u = URLComponents(string: url), let scheme = u.scheme, let host = u.host else { return url }
        return "\(scheme)://\(host)"
    }

    @MainActor
    private func ensureWebView() -> WKWebView {
        if let wv = webView { return wv }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        // Hook de fetch/XHR (en cada documento, antes de su JS) para poder capturar URLs firmadas.
        let hook = """
        (function(){ window.__cap = [];
          const of = window.fetch;
          window.fetch = function(...a){ try{ const u=(a[0]&&a[0].url)||a[0]; window.__cap.push(''+u);}catch(e){} return of.apply(this,a); };
          const ox = XMLHttpRequest.prototype.open;
          XMLHttpRequest.prototype.open = function(m,u){ try{ window.__cap.push(''+u);}catch(e){} return ox.apply(this,arguments); };
        })();
        """
        config.userContentController.addUserScript(
            WKUserScript(source: hook, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        wv.alpha = 0.01
        wv.isUserInteractionEnabled = false
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.first { $0.isKeyWindow }
        keyWindow?.addSubview(wv)
        webView = wv
        return wv
    }
}
