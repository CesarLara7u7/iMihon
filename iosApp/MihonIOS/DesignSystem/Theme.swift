import SwiftUI

/// Sistema de diseño mínimo. Cuando se conecte la lógica compartida (KMP),
/// aquí se mapearán los temas/colores que hoy viven en `presentation-core` (Android).
extension Color {
    /// Color de acento de la app. Ahora es DINÁMICO: lo define el usuario en Personalización
    /// (`AppSettings.accentColor`). Leerlo dentro de un `body` registra observación → reactivo.
    static var mihonAccent: Color { AppSettings.shared.accentColor }

    /// Acento de marca por defecto (índigo). Base del color personalizable.
    static let mihonAccentDefault = Color(red: 0.38, green: 0.40, blue: 0.95)

    /// Crea un color desde un hex "RRGGBB" (con o sin #).
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }

    /// Versión pastel (mezcla con blanco). `amount` = cuánto blanco (0…1).
    /// Para fondos/realces suaves que no cansan la vista en una app de lectura.
    func pastel(_ amount: Double = 0.55) -> Color {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let m = CGFloat(amount)
        return Color(red: Double(r + (1 - r) * m), green: Double(g + (1 - g) * m), blue: Double(b + (1 - b) * m))
    }

    /// Acento suave (pastel) para fondos y realces sin fatigar.
    static var mihonAccentSoft: Color { mihonAccent.pastel(0.5) }

    /// Ajusta el brillo del color (delta en -1…1) conservando matiz/saturación.
    func adjustBrightness(_ delta: Double) -> Color {
        let ui = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: Double(h), saturation: Double(s),
                     brightness: max(0, min(1, Double(b) + delta)))
    }

    /// Acento para TEXTO: tono oscuro del acento en modo claro, tono claro en modo oscuro
    /// (siempre legible, con el color elegido por el usuario).
    static var mihonAccentText: Color {
        let accent = mihonAccent
        return Color(UIColor { trait in
            UIColor(trait.userInterfaceStyle == .dark
                    ? accent.adjustBrightness(0.22)
                    : accent.adjustBrightness(-0.32))
        })
    }

    /// Devuelve el color como hex "RRGGBB".
    func toHex() -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    /// Genera un color estable a partir de un texto, para portadas placeholder.
    static func deterministic(from seed: String) -> Color {
        var hash = 5381
        for byte in seed.utf8 { hash = ((hash << 5) &+ hash) &+ Int(byte) }
        let hue = Double(abs(hash) % 360) / 360.0
        return Color(hue: hue, saturation: 0.45, brightness: 0.65)
    }
}

/// Portada placeholder mientras no haya carga de imágenes reales (Coil → Kingfisher/AsyncImage).
struct CoverPlaceholder: View {
    let title: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.deterministic(from: title), .deterministic(from: String(title.reversed()))],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(title.prefix(2).uppercased())
                .font(.title.bold())
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}
