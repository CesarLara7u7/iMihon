import Foundation

/// Espejo simplificado de `tachiyomi.domain.chapter.model.Chapter`.
struct Chapter: Identifiable, Hashable {
    let id: Int64
    var name: String
    var chapterNumber: Double
    var scanlator: String?
    var dateUpload: Date
    var read: Bool
    var bookmark: Bool
    var lastPageRead: Int

    /// Número total de páginas (mock). En producción viene de la fuente al cargar la página.
    var pageCount: Int
}
