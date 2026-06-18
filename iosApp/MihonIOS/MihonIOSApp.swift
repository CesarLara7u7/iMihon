import SwiftUI

/// Punto de entrada de la app. Equivalente a `App.kt` + `MainActivity` en Mihon.
@main
struct MihonIOSApp: App {
    init() {
        configureImageCache()
        // Comick y MangaFire van tras Cloudflare: sus peticiones se enrutan por un WKWebView.
        MockData.bridgeInstance.setWebFetcher(fetcher: WebViewFetcher.shared)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(.mihonAccent)
                .task {
                    // Retención: borra descargas caducadas al abrir la app.
                    DownloadManager.shared.applyRetention(
                        days: AppSettings.shared.retentionDays,
                        now: Date().timeIntervalSince1970
                    )
                    // Precarga Recientes al abrir la app (caché, refresca si >20 min).
                    await UpdatesStore.shared.loadIfNeeded()
                }
        }
    }

    /// Caché de imágenes en disco (portadas y páginas). `AsyncImage` usa `URLSession.shared`,
    /// que respeta `URLCache.shared`. Base para la futura implementación de descargas
    /// (que usará un almacén explícito y persistente aparte de esta caché temporal).
    private func configureImageCache() {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let imageCacheDir = cachesDir?.appendingPathComponent("ImageCache", isDirectory: true)
        URLCache.shared = URLCache(
            memoryCapacity: 64 * 1024 * 1024,    // 64 MB en RAM
            diskCapacity: 512 * 1024 * 1024,     // 512 MB en disco
            directory: imageCacheDir
        )
    }
}
