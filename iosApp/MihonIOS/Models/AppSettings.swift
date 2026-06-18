import SwiftUI

/// Ajustes globales de la app, persistidos en `UserDefaults`.
///
/// `incognito`: modo incógnito. Cuando está activo, el lector NO guarda historial ni
/// progreso de lectura (no deja rastro de lo que se lee). Las preferencias de lectura
/// (filtro, dirección…) sí se conservan: son ajustes de visualización, no rastro.
///
/// Los `default*` son los valores de lectura POR DEFECTO para manga que aún no tienen
/// preferencias propias guardadas. El lector los usa como base; cualquier ajuste hecho
/// en el manga (panel de opciones) se guarda aparte y tiene prioridad.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var incognito: Bool { didSet { d.set(incognito, forKey: Keys.incognito) } }

    var defaultColorFilter: Int { didSet { d.set(defaultColorFilter, forKey: Keys.colorFilter) } }
    var defaultIntensity: Double { didSet { d.set(defaultIntensity, forKey: Keys.intensity) } }
    var defaultDirection: Int { didSet { d.set(defaultDirection, forKey: Keys.direction) } }
    var defaultMode: Int { didSet { d.set(defaultMode, forKey: Keys.mode) } }
    var doublePageDefault: Bool { didSet { d.set(doublePageDefault, forKey: Keys.doublePage) } }
    /// Mostrar mensajes de descanso/continuar al final del capítulo.
    var restMessages: Bool { didSet { d.set(restMessages, forKey: Keys.restMessages) } }

    /// Retención de descargas en días (0 = nunca borrar automáticamente).
    var retentionDays: Int { didSet { d.set(retentionDays, forKey: Keys.retention) } }

    // ── Personalización ──
    /// Color de énfasis (hex "RRGGBB"). Base de `Color.mihonAccent`.
    var accentHex: String { didSet { d.set(accentHex, forKey: Keys.accentHex) } }
    /// Tema de fondo (0 = ninguno, 1..N degradados con nombre en `AppTheme`).
    var backgroundStyle: Int { didSet { d.set(backgroundStyle, forKey: Keys.background) } }
    /// Cristal más transparente (Liquid Glass `.clear` en iOS 26).
    var clearGlass: Bool { didSet { d.set(clearGlass, forKey: Keys.clearGlass) } }
    /// Emoji del patrón de fondo (estilo Telegram). "" = sin patrón.
    var patternEmoji: String { didSet { d.set(patternEmoji, forKey: Keys.pattern) } }
    /// Portada del último manga ABIERTO (al entrar a su detalle) — fondo dinámico de Biblioteca.
    var lastViewedCover: String { didSet { d.set(lastViewedCover, forKey: Keys.lastCover) } }

    // ── Apariencia ──
    /// Esquema de color: 0 = según el sistema, 1 = claro, 2 = oscuro.
    var appearance: Int { didSet { d.set(appearance, forKey: Keys.appearance) } }
    /// Fondo de Biblioteca con la portada del último manga abierto.
    var libraryCoverBackground: Bool { didSet { d.set(libraryCoverBackground, forKey: Keys.libBg) } }
    /// El fondo de Biblioteca se mueve suavemente con el giroscopio.
    var backgroundGyro: Bool { didSet { d.set(backgroundGyro, forKey: Keys.bgGyro) } }
    /// El cromo (portada ampliada) reacciona al giroscopio.
    var cardGyro: Bool { didSet { d.set(cardGyro, forKey: Keys.cardGyro) } }
    /// Modo una mano activo (se restaura al reabrir la app si quedó encendido).
    var oneHandMode: Bool { didSet { d.set(oneHandMode, forKey: Keys.oneHand) } }
    /// Partículas ambientales en los fondos.
    var particles: Bool { didSet { d.set(particles, forKey: Keys.particles) } }
    /// Fuentes DESACTIVADAS por el usuario (no se muestran en Explorar). Opt-out: vacío = todas on.
    var disabledSources: Set<String> { didSet { d.set(Array(disabledSources), forKey: Keys.disabledSources) } }
    /// Estanterías (categorías) CONTRAÍDAS en Biblioteca, por id de categoría.
    var collapsedShelves: Set<Int> { didSet { d.set(Array(collapsedShelves), forKey: Keys.collapsedShelves) } }
    /// Fuente PREDETERMINADA (id, p. ej. "mangadex-es"): por defecto en Explorar y Actualizaciones.
    var defaultSourceId: String { didSet { d.set(defaultSourceId, forKey: Keys.defaultSource) } }
    /// Si el usuario pidió no volver a ver el aviso al marcar la fuente predeterminada.
    var defaultSourceTipDismissed: Bool { didSet { d.set(defaultSourceTipDismissed, forKey: Keys.defaultSourceTip) } }
    /// Si el usuario pidió no volver a ver el aviso al marcar un manga como +18.
    var nsfwTipDismissed: Bool { didSet { d.set(nsfwTipDismissed, forKey: Keys.nsfwTip) } }

    func sourceEnabled(_ id: String) -> Bool { !disabledSources.contains(id) }

    /// Esquema de color para `.preferredColorScheme` (nil = sistema).
    var colorScheme: ColorScheme? {
        switch appearance { case 1: return .light; case 2: return .dark; default: return nil }
    }

    /// Acento como `Color` (bindable en un ColorPicker; al fijarlo persiste el hex).
    var accentColor: Color {
        get { Color(hex: accentHex) }
        set { accentHex = newValue.toHex() }
    }

    private let d = UserDefaults.standard

    private enum Keys {
        static let incognito = "settings.incognito"
        static let colorFilter = "settings.reader.colorFilter"
        static let intensity = "settings.reader.intensity"
        static let direction = "settings.reader.direction"
        static let mode = "settings.reader.mode"
        static let doublePage = "settings.reader.doublePage"
        static let restMessages = "settings.reader.restMessages"
        static let retention = "settings.downloads.retentionDays"
        static let accentHex = "settings.theme.accentHex"
        static let background = "settings.theme.background"
        static let clearGlass = "settings.theme.clearGlass"
        static let pattern = "settings.theme.patternEmoji"
        static let lastCover = "settings.lastViewedCover"
        static let appearance = "settings.appearance"
        static let libBg = "settings.libraryCoverBackground"
        static let bgGyro = "settings.backgroundGyro"
        static let cardGyro = "settings.cardGyro"
        static let oneHand = "settings.oneHandMode"
        static let particles = "settings.particles"
        static let disabledSources = "settings.disabledSources"
        static let collapsedShelves = "settings.collapsedShelves"
        static let defaultSource = "settings.defaultSourceId"
        static let defaultSourceTip = "settings.defaultSourceTipDismissed"
        static let nsfwTip = "settings.nsfwTipDismissed"
    }

    private init() {
        incognito = d.bool(forKey: Keys.incognito)
        defaultColorFilter = d.integer(forKey: Keys.colorFilter)               // 0 = ninguno
        defaultIntensity = d.object(forKey: Keys.intensity) as? Double ?? 1.0
        defaultDirection = d.object(forKey: Keys.direction) as? Int ?? 1        // 1 = RTL
        defaultMode = d.integer(forKey: Keys.mode)                             // 0 = paginado
        doublePageDefault = d.bool(forKey: Keys.doublePage)                    // false
        restMessages = d.object(forKey: Keys.restMessages) as? Bool ?? true
        retentionDays = d.integer(forKey: Keys.retention)                     // 0 = nunca
        accentHex = d.string(forKey: Keys.accentHex) ?? "6166F2"              // índigo de marca
        backgroundStyle = d.integer(forKey: Keys.background)                   // 0 = ninguno
        clearGlass = d.bool(forKey: Keys.clearGlass)                          // false
        patternEmoji = d.string(forKey: Keys.pattern) ?? ""                   // sin patrón
        lastViewedCover = d.string(forKey: Keys.lastCover) ?? ""
        appearance = d.integer(forKey: Keys.appearance)                       // 0 = sistema
        libraryCoverBackground = d.object(forKey: Keys.libBg) as? Bool ?? true
        backgroundGyro = d.object(forKey: Keys.bgGyro) as? Bool ?? true
        cardGyro = d.object(forKey: Keys.cardGyro) as? Bool ?? true
        oneHandMode = d.bool(forKey: Keys.oneHand)
        particles = d.object(forKey: Keys.particles) as? Bool ?? true   // por defecto, on
        disabledSources = Set(d.array(forKey: Keys.disabledSources) as? [String] ?? [])
        collapsedShelves = Set(d.array(forKey: Keys.collapsedShelves) as? [Int] ?? [])
        defaultSourceId = d.string(forKey: Keys.defaultSource) ?? ""
        defaultSourceTipDismissed = d.bool(forKey: Keys.defaultSourceTip)
        nsfwTipDismissed = d.bool(forKey: Keys.nsfwTip)
    }
}
