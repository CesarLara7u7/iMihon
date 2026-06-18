import Foundation

/// Espejo simplificado de una fuente/extensión (`eu.kanade.tachiyomi.source.Source`).
///
/// NOTA DE MIGRACIÓN: en Android las fuentes son APKs cargados dinámicamente, algo que
/// iOS no permite. La estrategia de fuentes online (backend tipo Tachidesk vs. solo local)
/// sigue pendiente de decidir; por ahora son datos mock.
struct MangaSource: Identifiable, Hashable {
    let id: Int64
    var name: String
    var language: String
    var isLocal: Bool
}
