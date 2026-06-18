import SwiftUI
import CryptoKit
import Shared

/// Estado de una descarga (capítulo). Espejo en memoria de la fila de SQLite.
struct DownloadItem: Identifiable, Equatable {
    enum Status: Int { case queued = 0, downloading = 1, done = 2, failed = 3 }

    let sourceId: String
    let mangaId: String
    let chapterId: String
    let mangaTitle: String
    let thumbnailUrl: String?
    let chapterName: String
    var totalPages: Int
    var downloadedPages: Int
    var status: Status

    var id: String { DownloadManager.key(sourceId, mangaId, chapterId) }
    var fraction: Double { totalPages > 0 ? Double(downloadedPages) / Double(totalPages) : 0 }
}

/// Gestor de descargas: cola SERIAL (un capítulo a la vez, amable con la red), guarda las
/// páginas en `Documents/Downloads/<hash>/` (persistente, no se purga como la caché) y
/// refleja el estado en SQLite para que sobreviva entre lanzamientos.
@MainActor
@Observable
final class DownloadManager {
    static let shared = DownloadManager()

    /// Estado vivo por capítulo (clave = key(source,manga,chapter)).
    private(set) var items: [String: DownloadItem] = [:]

    private var queue: [DownloadItem] = []
    private var running = false
    private var cancelled: Set<String> = []

    private let root: URL
    private let bridge = MockData.bridgeInstance
    private let session = URLSession(configuration: .default)

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = docs.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        hydrate()
        resumeInterrupted()
    }

    /// Reanuda descargas que quedaron a medias (la app se cerró mientras descargaba o estaban
    /// en cola). Vuelven a la cola; `process` saltará las páginas que ya estén en disco.
    private func resumeInterrupted() {
        let pending = items.values
            .filter { $0.status == .downloading || $0.status == .queued }
            .sorted { $0.chapterName < $1.chapterName }
        for it in pending {
            update(it.id) { $0.status = .queued }
            persistProgress(it.id)
            if let item = items[it.id] { queue.append(item) }
        }
        pump()
    }

    nonisolated static func key(_ s: String, _ m: String, _ c: String) -> String { "\(s)|\(m)|\(c)" }

    // MARK: - Consulta

    func item(_ s: String, _ m: String, _ c: String) -> DownloadItem? {
        items[Self.key(s, m, c)]
    }

    func isDownloaded(_ s: String, _ m: String, _ c: String) -> Bool {
        items[Self.key(s, m, c)]?.status == .done && FileManager.default.fileExists(atPath: doneMarker(s, m, c).path)
    }

    /// URLs locales (file://) de las páginas si el capítulo está completo; si no, nil.
    func localPages(_ s: String, _ m: String, _ c: String) -> [String]? {
        guard isDownloaded(s, m, c),
              let countStr = try? String(contentsOf: doneMarker(s, m, c), encoding: .utf8),
              let count = Int(countStr.trimmingCharacters(in: .whitespacesAndNewlines)), count > 0
        else { return nil }
        let dir = chapterDir(s, m, c)
        return (0..<count).map { dir.appendingPathComponent("\($0).img").absoluteString }
    }

    /// Todas las descargas agrupadas por manga (para la pantalla de gestión).
    var grouped: [(title: String, items: [DownloadItem])] {
        Dictionary(grouping: items.values, by: { $0.mangaId })
            .map { (title: $0.value.first?.mangaTitle ?? "", items: $0.value.sorted { $0.chapterName < $1.chapterName }) }
            .sorted { $0.title < $1.title }
    }

    // MARK: - Acciones

    func download(sourceId: String, mangaId: String, mangaTitle: String, thumbnailUrl: String?,
                  chapterId: String, chapterName: String) {
        let k = Self.key(sourceId, mangaId, chapterId)
        if isDownloaded(sourceId, mangaId, chapterId) || items[k]?.status == .queued || items[k]?.status == .downloading {
            return
        }
        cancelled.remove(k)
        let item = DownloadItem(sourceId: sourceId, mangaId: mangaId, chapterId: chapterId,
                                mangaTitle: mangaTitle, thumbnailUrl: thumbnailUrl, chapterName: chapterName,
                                totalPages: 0, downloadedPages: 0, status: .queued)
        items[k] = item
        persist(item)
        queue.append(item)
        pump()
    }

    /// Encola varios capítulos (descarga de serie completa).
    func downloadSeries(sourceId: String, mangaId: String, mangaTitle: String, thumbnailUrl: String?,
                        chapters: [(id: String, name: String)]) {
        for ch in chapters {
            download(sourceId: sourceId, mangaId: mangaId, mangaTitle: mangaTitle,
                     thumbnailUrl: thumbnailUrl, chapterId: ch.id, chapterName: ch.name)
        }
    }

    func delete(_ s: String, _ m: String, _ c: String) {
        let k = Self.key(s, m, c)
        cancelled.insert(k)
        queue.removeAll { $0.id == k }
        try? FileManager.default.removeItem(at: chapterDir(s, m, c))
        items[k] = nil
        try? bridge.deleteDownload(sourceId: s, mangaId: m, chapterId: c)
    }

    func deleteManga(_ s: String, _ m: String) {
        for it in items.values where it.sourceId == s && it.mangaId == m {
            delete(s, m, it.chapterId)
        }
    }

    func deleteAll() {
        for it in items.values { delete(it.sourceId, it.mangaId, it.chapterId) }
    }

    /// Retención: borra descargas completadas con más de `days` días (0 = nunca).
    func applyRetention(days: Int, now: Double) {
        guard days > 0 else { return }
        let cutoff = Int64((now - Double(days) * 86_400) * 1000)
        let stale = (try? bridge.downloadsCompletedBefore(cutoff: cutoff)) ?? []
        for e in stale {
            try? FileManager.default.removeItem(at: chapterDir(e.sourceId, e.mangaId, e.chapterId))
            items[Self.key(e.sourceId, e.mangaId, e.chapterId)] = nil
        }
        try? bridge.deleteDownloadsCompletedBefore(cutoff: cutoff)
    }

    // MARK: - Cola

    private func pump() {
        guard !running, let next = queue.first else { return }
        running = true
        Task {
            await process(next)
            queue.removeFirst()
            running = false
            pump()
        }
    }

    private func process(_ item: DownloadItem) async {
        let k = item.id
        guard !cancelled.contains(k) else { return }
        update(k) { $0.status = .downloading }
        persistProgress(k)
        do {
            let pages = try await bridge.chapterPages(sourceId: item.sourceId, chapterId: item.chapterId)
            guard !pages.isEmpty else { throw DLError.noPages }
            update(k) { $0.totalPages = pages.count }
            persistProgress(k)

            let dir = chapterDir(item.sourceId, item.mangaId, item.chapterId)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            for (i, urlString) in pages.enumerated() {
                if cancelled.contains(k) { return }
                let file = dir.appendingPathComponent("\(i).img")
                // Reanudación: si la página ya se bajó (escritura atómica = nunca a medias), se salta.
                if FileManager.default.fileExists(atPath: file.path) {
                    update(k) { $0.downloadedPages = max($0.downloadedPages, i + 1) }
                    continue
                }
                guard let url = URL(string: urlString) else { continue }
                let data = try await Self.fetch(url, session: session)
                try Self.write(data, to: file)
                update(k) { $0.downloadedPages = i + 1 }
                if i % 3 == 0 || i == pages.count - 1 { persistProgress(k) }
            }
            // Marcador de "completo" con el número total de páginas.
            try Self.write(Data("\(pages.count)".utf8), to: doneMarker(item.sourceId, item.mangaId, item.chapterId))
            update(k) { $0.status = .done }
            persistProgress(k)
        } catch {
            update(k) { $0.status = .failed }
            persistProgress(k)
        }
    }

    // MARK: - Helpers de estado / disco

    private func update(_ k: String, _ change: (inout DownloadItem) -> Void) {
        guard var it = items[k] else { return }
        change(&it)
        items[k] = it
    }

    private func hydrate() {
        let entries = (try? bridge.downloads()) ?? []
        for e in entries {
            items[Self.key(e.sourceId, e.mangaId, e.chapterId)] = DownloadItem(
                sourceId: e.sourceId, mangaId: e.mangaId, chapterId: e.chapterId,
                mangaTitle: e.mangaTitle, thumbnailUrl: e.thumbnailUrl, chapterName: e.chapterName,
                totalPages: Int(e.totalPages), downloadedPages: Int(e.downloadedPages),
                status: DownloadItem.Status(rawValue: Int(e.status)) ?? .queued
            )
        }
    }

    private func persist(_ it: DownloadItem) {
        try? bridge.upsertDownload(
            sourceId: it.sourceId, mangaId: it.mangaId, chapterId: it.chapterId,
            mangaTitle: it.mangaTitle, thumbnailUrl: it.thumbnailUrl, chapterName: it.chapterName,
            totalPages: Int32(it.totalPages), downloadedPages: Int32(it.downloadedPages),
            status: Int32(it.status.rawValue), createdAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }

    private func persistProgress(_ k: String) {
        guard let it = items[k] else { return }
        try? bridge.updateDownloadProgress(
            sourceId: it.sourceId, mangaId: it.mangaId, chapterId: it.chapterId,
            totalPages: Int32(it.totalPages), downloadedPages: Int32(it.downloadedPages),
            status: Int32(it.status.rawValue)
        )
    }

    private func chapterDir(_ s: String, _ m: String, _ c: String) -> URL {
        let digest = SHA256.hash(data: Data(Self.key(s, m, c).utf8))
        return root.appendingPathComponent(digest.map { String(format: "%02x", $0) }.joined(), isDirectory: true)
    }

    private func doneMarker(_ s: String, _ m: String, _ c: String) -> URL {
        chapterDir(s, m, c).appendingPathComponent("done.txt")
    }

    private nonisolated static func fetch(_ url: URL, session: URLSession) async throws -> Data {
        // Enruta por ImageCache: añade cabeceras de MANGA Plus y descifra (XOR) si aplica,
        // de modo que las páginas se guardan ya descifradas y se leen offline igual que el resto.
        try await ImageCache.fetchData(for: url, session: session)
    }

    private nonisolated static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    private enum DLError: Error { case noPages }
}
