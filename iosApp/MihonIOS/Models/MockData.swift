import Foundation
import Shared

/// Adaptador entre el módulo Kotlin compartido (`Shared`) y los modelos Swift de la UI.
///
/// FASE 1: la "fuente de verdad" de los datos ya NO está en Swift, sino en Kotlin
/// (`MihonShared` → `SampleLibraryRepository`). Aquí solo se mapean los tipos Kotlin
/// a los structs Swift que consumen las vistas. En la Fase 2 el repositorio Kotlin
/// pasará a estar respaldado por SQLDelight, sin tocar la UI.
extension Shared.BrowseManga {
    /// Identidad ESTABLE y única para listas (`fuente|id`). Evita colisiones cuando dos manga
    /// comparten `id` entre fuentes (causaba abrir el manga equivocado en estantes como Tendencia).
    var compositeKey: String { "\(sourceId)|\(id)" }
}

enum MockData {
    private static let bridge = MihonShared()

    /// Acceso a la fachada Kotlin compartida para pantallas que la necesiten.
    static var bridgeInstance: MihonShared { bridge }

    /// Nombre de plataforma reportado por el código nativo iOS del módulo compartido.
    static let platform: String = bridge.platform()

    /// Guarda/quita un manga de la biblioteca desde cualquier portada (sin entrar al detalle).
    /// Devuelve `true` si la operación tuvo éxito.
    @discardableResult
    static func setFavorite(sourceId: String, mangaId: String, title: String,
                            thumbnail: String?, favorite: Bool) -> Bool {
        do {
            try bridge.setFavorite(
                sourceId: sourceId, mangaId: mangaId, title: title,
                thumbnailUrl: thumbnail, favorite: favorite,
                now: Int64(Date().timeIntervalSince1970 * 1000)
            )
            return true
        } catch {
            return false
        }
    }

    static let library: [Manga] = bridge.library().map { map($0) }

    static let catalogue: [Manga] = library

    static let sources: [MangaSource] = [
        .init(id: 1, name: "MangaDex", language: "es", isLocal: false),
        .init(id: 2, name: "ComicK", language: "en", isLocal: false),
        .init(id: 3, name: "Local", language: "all", isLocal: true),
    ]


    // MARK: - Mapeo Kotlin → Swift

    private static func map(_ m: Shared.Manga) -> Manga {
        let chapters = bridge.chapters(mangaId: m.id).map { map($0) }
        return Manga(
            id: m.id,
            title: m.title,
            author: m.author ?? "Desconocido",
            artist: m.artist ?? "",
            description: m.description_ ?? "",
            genres: m.genre ?? [],
            status: mapStatus(m.status),
            sourceName: bridge.sourceName(sourceId: m.source),
            inLibrary: m.favorite,
            unreadCount: Int(bridge.unreadCount(mangaId: m.id)),
            chapters: chapters
        )
    }

    private static func map(_ c: Shared.Chapter) -> Chapter {
        Chapter(
            id: c.id,
            name: c.name,
            chapterNumber: c.chapterNumber,
            scanlator: c.scanlator,
            dateUpload: Date(timeIntervalSince1970: TimeInterval(c.dateUpload) / 1000.0),
            read: c.read,
            bookmark: c.bookmark,
            lastPageRead: Int(c.lastPageRead),
            // pageCount aún no existe en el dominio compartido; se sintetiza por ahora.
            pageCount: 12 + Int(c.id % 17)
        )
    }

    private static func mapStatus(_ status: Int64) -> MangaStatus {
        // Valores espejo de los estados de Mihon (SManga): 0..6
        switch status {
        case 1: return .ongoing
        case 2: return .completed
        case 3: return .licensed
        case 5: return .cancelled
        case 6: return .hiatus
        default: return .unknown
        }
    }
}
