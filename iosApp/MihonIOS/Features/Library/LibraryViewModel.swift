import Foundation
import Observation

/// Equivale a `LibraryScreenModel.kt`. Usa `@Observable` (iOS 17+), el patrón moderno
/// de SwiftUI que sustituye al `StateScreenModel`/StateFlow de Voyager.
@Observable
final class LibraryViewModel {
    var searchQuery: String = ""
    private(set) var allManga: [Manga] = MockData.library

    var filteredManga: [Manga] {
        guard !searchQuery.isEmpty else { return allManga }
        return allManga.filter { $0.title.localizedCaseInsensitiveContains(searchQuery) }
    }

    var totalUnread: Int {
        allManga.reduce(0) { $0 + $1.unreadCount }
    }
}
