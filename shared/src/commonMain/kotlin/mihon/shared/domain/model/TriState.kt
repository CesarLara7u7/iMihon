package mihon.shared.domain.model

/** Portado de `tachiyomi.core.common.preference.TriState` (Mihon). */
enum class TriState {
    DISABLED,
    ENABLED_IS,
    ENABLED_NOT,
    ;

    fun next(): TriState = when (this) {
        DISABLED -> ENABLED_IS
        ENABLED_IS -> ENABLED_NOT
        ENABLED_NOT -> DISABLED
    }
}
