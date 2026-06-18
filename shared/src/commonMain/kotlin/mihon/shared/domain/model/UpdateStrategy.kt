package mihon.shared.domain.model

/**
 * Estrategia de actualización de una serie. Portado de
 * `eu.kanade.tachiyomi.source.model.UpdateStrategy` (Mihon).
 */
enum class UpdateStrategy {
    ALWAYS_UPDATE,
    ONLY_FETCH_ONCE,
}
