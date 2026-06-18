import SwiftUI

/// Kaomoji (emoticones japoneses) para dar carácter a los textos de carga/estado.
enum Kaomoji {
    static let loading = ["(｀・ω・´)ゞ", "(っ˘ω˘ς )", "ヽ(•‿•)ノ", "(◕‿◕)", "(～￣▽￣)～"]
    static let empty = ["(╥﹏╥)", "(´･_･`)", "(；一_一)", "┐(￣ヘ￣)┌"]
    static let error = ["(╯°□°）╯", "(˘･_･˘)", "(>_<)"]

    /// Elección estable por longitud del texto (sin aleatoriedad).
    static func pick(_ set: [String], seed: Int) -> String { set[abs(seed) % set.count] }
}

/// Estado de carga atractivo: spinner + texto con kaomoji, sobre el fondo temático (rellena todo).
struct LoadingState: View {
    let text: String
    var seed: Int = 3

    var body: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("\(text)  \(Kaomoji.pick(Kaomoji.loading, seed: seed))")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// Esqueleto animado (shimmer) para filas de lista mientras carga. Pocas filas, tono suave y
/// coherente con la fila real (miniatura 44×62 + dos líneas de texto).
struct SkeletonRows: View {
    var count = 5

    private var fill: Color { Color.primary.opacity(0.06) }

    var body: some View {
        VStack(spacing: 18) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fill)
                        .frame(width: 44, height: 62)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4).fill(fill).frame(height: 12).frame(maxWidth: .infinity)
                        RoundedRectangle(cornerRadius: 4).fill(fill).frame(width: 150, height: 10)
                    }
                    Spacer()
                }
            }
        }
        .shimmering()
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

extension View {
    /// Brillo desplazándose (efecto "loading") para skeletons.
    func shimmering() -> some View { modifier(Shimmering()) }
}

private struct Shimmering: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.22), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.45)
                        .offset(x: phase * geo.size.width * 1.6)
                }
                .mask(content)
                .allowsHitTesting(false)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.7).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}
