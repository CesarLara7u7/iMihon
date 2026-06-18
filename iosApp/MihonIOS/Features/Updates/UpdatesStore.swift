import SwiftUI
import Shared

/// Caché compartida de "Recientes": carga al abrir la app, conserva resultados entre cambios de
/// pestaña, refresca manual (pull-to-refresh) y se auto-refresca si pasaron 20 min.
@MainActor
@Observable
final class UpdatesStore {
    static let shared = UpdatesStore()

    enum Phase: Equatable { case loading, ready, failed(String) }

    private(set) var updates: [RecentUpdate] = []
    private(set) var phase: Phase = .loading

    private var lastFetch: Date?
    private var loading = false
    private let staleInterval: TimeInterval = 20 * 60   // 20 minutos

    /// Carga solo si no hay datos o si la caché tiene más de 20 min.
    func loadIfNeeded() async {
        if let last = lastFetch, Date().timeIntervalSince(last) < staleInterval, !updates.isEmpty { return }
        await refresh()
    }

    /// Recarga forzada (deslizar para refrescar / reintentar).
    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        if updates.isEmpty { phase = .loading }
        do {
            updates = try await MockData.bridgeInstance.recentUpdates(
                preferredSourceId: AppSettings.shared.defaultSourceId)
            lastFetch = Date()
            phase = .ready
        } catch {
            if updates.isEmpty { phase = .failed(error.localizedDescription) }
        }
    }
}
