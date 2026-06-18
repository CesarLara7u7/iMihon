import SwiftUI

extension View {
    /// Estilo "tarjeta" para portadas: recorte redondeado + contorno fino + sombra contenida.
    func coverCard(cornerRadius: CGFloat = 10) -> some View {
        clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.16), radius: 3, y: 2)
    }
}

/// Botón de tarjeta: efecto **zoom-in** notorio al tocar (pop con resorte) + realce de sombra contenido.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.12 : 1)
            .shadow(color: Color.mihonAccent.opacity(configuration.isPressed ? 0.4 : 0),
                    radius: configuration.isPressed ? 7 : 0, y: 2)
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

extension View {
    /// Borde "coleccionable" estilo Wii U: contorno transparente + un **brillo que gira** alrededor
    /// (cromo). El destello recorre el perímetro en bucle.
    func collectibleBorder(cornerRadius: CGFloat = 10) -> some View {
        modifier(CollectibleBorder(cornerRadius: cornerRadius))
    }

    /// Fila de lista como tarjeta de cristal flotante: integra con el fondo temático
    /// (transparencia, sombra y separadores limpios) en Recientes/Historial.
    func glassListRow() -> some View {
        listRowBackground(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                .padding(.vertical, 4)
        )
        .listRowSeparator(.hidden)
    }
}

/// Texto que se revela con efecto **typewriter** (con cursor) — limpio, sin solaparse.
struct TypewriterText: View {
    let text: String
    var font: Font = .subheadline.weight(.light)
    var color: Color = .mihonAccentText

    @State private var visible = 0

    var body: some View {
        HStack(spacing: 1) {
            Text(String(text.prefix(visible)))
                .font(font).foregroundStyle(color)
            if visible < text.count {
                Text("▌").font(font).foregroundStyle(Color.mihonAccent)
            }
        }
        .task(id: text) {
            visible = 0
            for i in 0...text.count {
                visible = i
                try? await Task.sleep(nanoseconds: 32_000_000)
            }
        }
    }
}

/// Borde "cromo": marco visible de cristal + un **reflejo** que barre en diagonal de forma suave
/// (como la luz sobre el plástico de una carta coleccionable).
struct CollectibleBorder: ViewModifier {
    var cornerRadius: CGFloat
    // El destello cruza la portada al inicio del ciclo (~2-3 s) y luego espera fuera de cuadro;
    // ciclo total de 30 s ⇒ "ocurrencia casi cada 30 s". Recorrido grande -1.4→16 a velocidad lenta.
    @State private var sweep: CGFloat = -1.4

    func body(content: Content) -> some View {
        content
            // Marco de cristal visible (5 pt) SOLO translúcido (sin acento, no desentona la portada).
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.15), .white.opacity(0.45)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 5
                    )
            )
            // Reflejo: franja diagonal que recorre SOLO el marco (enmascarada al borde, no a la portada).
            .overlay {
                GeometryReader { geo in
                    Rectangle()
                        .fill(LinearGradient(colors: [.clear, .white.opacity(0.6), .clear],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * 0.55)
                        .frame(maxHeight: .infinity)
                        .rotationEffect(.degrees(18))
                        .offset(x: sweep * geo.size.width)
                        .blendMode(.plusLighter)
                }
                .mask(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white, lineWidth: 5)
                )
                .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(.linear(duration: 30).repeatForever(autoreverses: false)) {
                    sweep = 16
                }
            }
    }
}
