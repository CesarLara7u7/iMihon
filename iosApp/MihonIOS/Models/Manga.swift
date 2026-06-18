import Foundation

/// Espejo simplificado de `tachiyomi.domain.manga.model.Manga`.
/// Cuando se integre KMP, este tipo se reemplazará por el modelo compartido (o un mapper a él).
struct Manga: Identifiable, Hashable {
    let id: Int64
    var title: String
    var author: String
    var artist: String
    var description: String
    var genres: [String]
    var status: MangaStatus
    var sourceName: String
    var inLibrary: Bool
    var unreadCount: Int
    var chapters: [Chapter]
}

enum MangaStatus: String, CaseIterable {
    case unknown = "Desconocido"
    case ongoing = "En emisión"
    case completed = "Completado"
    case licensed = "Licenciado"
    case hiatus = "En pausa"
    case cancelled = "Cancelado"
}
