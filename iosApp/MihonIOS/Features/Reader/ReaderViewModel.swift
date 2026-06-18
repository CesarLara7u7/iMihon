import Foundation
import Observation

/// Equivale a `ReaderViewModel.kt`. En el esqueleto las "páginas" son placeholders de color.
@Observable
final class ReaderViewModel {
    let manga: Manga
    let chapter: Chapter
    var currentPage: Int
    var showControls: Bool = true

    init(manga: Manga, chapter: Chapter) {
        self.manga = manga
        self.chapter = chapter
        self.currentPage = chapter.lastPageRead
    }

    var pageCount: Int { chapter.pageCount }

    var progressText: String { "\(currentPage + 1) / \(pageCount)" }
}
