import SwiftUI
import Shared

/// Búsqueda global en **streaming**: lanza una consulta por fuente (concurrencia limitada) y va
/// publicando cada grupo en cuanto su fuente responde, sin esperar a todas.
///
/// Es un singleton `@Observable`: la tarea de búsqueda la posee el store, no la vista, así que
/// entrar a un manga encontrado NO cancela la búsqueda — sigue en segundo plano. Solo una
/// consulta NUEVA cancela la anterior.
@MainActor
@Observable
final class SearchStore {
    static let shared = SearchStore()

    enum Phase { case idle, searching, done }

    private(set) var query = ""
    private(set) var groups: [SearchGroup] = []
    private(set) var phase: Phase = .idle

    private var task: Task<Void, Never>?

    /// Lanza la búsqueda. Si [query] es igual a la actual y ya hay resultados, no reinicia.
    func run(query: String, sourceIds: [String]) {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { clear(); return }
        if q == self.query && phase != .idle { return }   // ya en curso / hecha para esta query
        task?.cancel()
        self.query = q
        groups = []
        phase = .searching
        let bridge = MockData.bridgeInstance
        task = Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                var iterator = sourceIds.makeIterator()
                func addNext() {
                    guard let id = iterator.next() else { return }
                    group.addTask {
                        let result = try? await bridge.searchSource(sourceId: id, query: q)
                        await MainActor.run {
                            guard !Task.isCancelled, self.query == q else { return }
                            if let result, !result.manga.isEmpty { self.append(result) }
                        }
                    }
                }
                for _ in 0..<4 { addNext() }                 // hasta 4 fuentes a la vez
                for await _ in group {
                    if Task.isCancelled { break }
                    addNext()
                }
            }
            if !Task.isCancelled, self.query == q { phase = .done }
        }
    }

    func clear() {
        task?.cancel()
        query = ""
        groups = []
        phase = .idle
    }

    private func append(_ g: SearchGroup) {
        groups.append(g)
        groups.sort { $0.sourceName == $1.sourceName ? $0.lang < $1.lang : $0.sourceName < $1.sourceName }
    }
}
