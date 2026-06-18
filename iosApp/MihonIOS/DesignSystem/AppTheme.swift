import SwiftUI

/// Temas de fondo (degradados suaves) elegibles en Personalización. Índice 0 = "Ninguno".
enum AppTheme {
    static let names = ["Ninguno", "Aurora", "Atardecer", "Océano", "Bosque", "Noche", "Caramelo"]

    /// Gris adaptable de cierre: blanco grisáceo en claro, negro grisáceo en oscuro.
    static var endGray: Color {
        Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(white: 0.13, alpha: 1) : UIColor(white: 0.96, alpha: 1) })
    }

    /// Gris pastel superior para el tema "Ninguno" (claro/oscuro adaptable).
    static var softGray: Color {
        Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(white: 0.20, alpha: 1) : UIColor(white: 0.90, alpha: 1) })
    }

    /// Degradado del tema `style`: del color elegido → gris claro/oscuro.
    /// "Ninguno" (0) usa un degradado de grises PASTEL suave (no deja el fondo plano).
    static func gradient(_ style: Int, accent: Color) -> LinearGradient {
        let top: Color
        switch style {
        case 1: top = accent
        case 2: top = Color(hex: "FF7E5F")
        case 3: top = Color(hex: "2193B0")
        case 4: top = Color(hex: "11998E")
        case 5: top = Color(hex: "654EA3")
        case 6: top = Color(hex: "FF6FD8")
        default:
            return LinearGradient(colors: [softGray, endGray], startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(
            colors: [top.opacity(0.45), top.opacity(0.16), endGray],
            startPoint: .top, endPoint: .bottom
        )
    }
}

/// Patrón de emoji repetido (estilo fondo de chat de Telegram), tenue, detrás del contenido.
struct EmojiPattern: View {
    let emoji: String

    var body: some View {
        Canvas { ctx, size in
            guard !emoji.isEmpty else { return }
            let step: CGFloat = 58
            let resolved = ctx.resolve(Text(emoji).font(.system(size: 24)))
            var y: CGFloat = 0
            var row = 0
            while y < size.height + step {
                let offset: CGFloat = (row % 2 == 0) ? 0 : step / 2
                var x: CGFloat = -step
                while x < size.width + step {
                    ctx.draw(resolved, at: CGPoint(x: x + offset, y: y))
                    x += step
                }
                y += step
                row += 1
            }
        }
        .opacity(0.10)
        .allowsHitTesting(false)
    }
}

extension View {
    /// Fondo temático elegido en Personalización: degradado + patrón de emoji (tenue).
    /// "Ninguno"/sin emoji deja el fondo del sistema. Reactivo (lee `AppSettings` en el body).
    @ViewBuilder func themedBackground() -> some View {
        let s = AppSettings.shared
        scrollContentBackground(.hidden)
            .background {
                ZStack {
                    AppTheme.gradient(s.backgroundStyle, accent: s.accentColor)
                    if !s.patternEmoji.isEmpty { EmojiPattern(emoji: s.patternEmoji) }
                    if s.particles { ParticleField() }
                }
                .ignoresSafeArea()
            }
    }
}
