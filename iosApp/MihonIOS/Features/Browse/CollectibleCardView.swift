import SwiftUI
import CoreMotion

/// Lee la orientación del dispositivo (giroscopio) para inclinar el cromo. En el simulador
/// no hay sensores → roll/pitch quedan en 0 y el arrastre con el dedo hace de respaldo.
@Observable
final class MotionManager {
    var roll: Double = 0
    var pitch: Double = 0
    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let m = motion else { return }
            self.roll = m.attitude.roll
            self.pitch = m.attitude.pitch
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }
}

/// Portada como **cromo coleccionable**: reflejo holográfico que sigue la inclinación
/// (giroscopio + arrastre), **volteo 3D** al tocar (cara trasera con la ficha) y borde brillante.
struct CollectibleCardView: View {
    let imageURL: String?
    let title: String
    let author: String?
    let status: String?
    let genres: [String]
    let onClose: () -> Void

    @State private var motion = MotionManager()
    @State private var flipped = false
    @State private var drag: CGSize = .zero
    @State private var appear = false
    @State private var sweep: CGFloat = -1.4

    private let radius: CGFloat = 22

    // Inclinación combinada (giroscopio + arrastre), limitada para no marear.
    // El giroscopio vertical (pitch) va INVERTIDO respecto a antes (estaba al revés).
    private var gyroRoll: Double { AppSettings.shared.cardGyro ? motion.roll : 0 }
    private var gyroPitch: Double { AppSettings.shared.cardGyro ? motion.pitch : 0 }
    private var tiltX: Double { clamp(Double(-drag.height / 9) - gyroPitch * 20) }
    private var tiltY: Double { clamp(Double(drag.width / 9) + gyroRoll * 20) }
    private func clamp(_ v: Double) -> Double { max(-22, min(22, v)) }

    var body: some View {
        GeometryReader { geo in
            let w = min(geo.size.width * 0.74, 300)
            ZStack {
                Color.black.opacity(0.62).ignoresSafeArea()
                    .onTapGesture { onClose() }

                cardStack(width: w)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            if AppSettings.shared.cardGyro { motion.start() }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { appear = true }
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) { sweep = 3.5 }
        }
        .onDisappear { motion.stop() }
        .transition(.opacity)
    }

    private func cardStack(width: CGFloat) -> some View {
        ZStack {
            front(width: width).opacity(flipped ? 0 : 1)
            back(width: width)
                .opacity(flipped ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .frame(width: width, height: width * 1.5)
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .rotation3DEffect(.degrees(tiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
        .rotation3DEffect(.degrees(tiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .scaleEffect(appear ? 1 : 0.82)
        .shadow(color: .black.opacity(0.5), radius: 22, y: 14)
        .gesture(
            DragGesture()
                .onChanged { drag = $0.translation }
                .onEnded { _ in withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { drag = .zero } }
        )
        .onTapGesture {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { flipped.toggle() }
        }
    }

    // MARK: - Cara frontal (portada + holograma)

    private func front(width: CGFloat) -> some View {
        let h = width * 1.5
        return ZStack {
            CachedImage(url: URL(string: imageURL ?? "")) { CoverPlaceholder(title: title) }
                .scaledToFill()
                .frame(width: width, height: h)

            holographicSheen(width: width, height: h)
            reflectionSweep(width: width)

            VStack {
                Spacer()
                Text(title)
                    .font(.subheadline.bold()).foregroundStyle(.white)
                    .lineLimit(2).multilineTextAlignment(.center)
                    .padding(8).frame(maxWidth: .infinity)
                    .background(.black.opacity(0.35), in: Rectangle())
            }
        }
        .frame(width: width, height: h)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(shineBorder)
    }

    /// Reflejo iridiscente (cromo) que cubre TODA la carta y se desplaza con la inclinación.
    /// Se dibuja más grande que la carta y se recorta, para que nunca se desborde.
    private func holographicSheen(width: CGFloat, height: CGFloat) -> some View {
        LinearGradient(
            colors: [.clear, .white.opacity(0.45), Color.mihonAccent.opacity(0.35),
                     .cyan.opacity(0.30), .pink.opacity(0.30), .clear],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .frame(width: width * 1.8, height: height * 1.8)
        .blendMode(.plusLighter)
        .opacity(0.55)
        .offset(x: CGFloat(tiltY) * 2.4, y: CGFloat(tiltX) * 2.4)
        .allowsHitTesting(false)
    }

    /// Franja de brillo diagonal que barre la carta (el efecto que pediste trasladar aquí).
    private func reflectionSweep(width: CGFloat) -> some View {
        Rectangle()
            .fill(LinearGradient(colors: [.clear, .white.opacity(0.5), .clear],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(width: width * 0.5)
            .frame(maxHeight: .infinity)
            .rotationEffect(.degrees(20))
            .offset(x: sweep * width)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }

    // MARK: - Cara trasera (ficha)

    private func back(width: CGFloat) -> some View {
        let h = width * 1.5
        return ZStack {
            // Fondo: la misma portada, difuminada + oscurecida + B/N (como el fondo de Biblioteca).
            CachedImage(url: URL(string: imageURL ?? "")) { Color.black }
                .scaledToFill()
                .frame(width: width, height: h)
                .grayscale(1)
                .blur(radius: 12)
                .overlay(Color.black.opacity(0.55))

            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline.weight(.bold)).foregroundStyle(.white).lineLimit(3)
                if let author, !author.isEmpty {
                    Label(author, systemImage: "person").font(.subheadline).foregroundStyle(.white.opacity(0.85))
                }
                if let status, !status.isEmpty {
                    Label(status, systemImage: "circle.fill")
                        .font(.caption).foregroundStyle(Color.mihonAccent.pastel(0.35))
                }
                if !genres.isEmpty {
                    FlowChips(items: Array(genres.prefix(6)))
                }
                Spacer()
                Label("Toca para voltear · inclina para ver el brillo", systemImage: "hand.tap")
                    .font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
            .padding(16)
            .frame(width: width, height: h, alignment: .topLeading)
        }
        .frame(width: width, height: h)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(shineBorder)
    }

    private var shineBorder: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(
                LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.1),
                                        Color.mihonAccent.opacity(0.6), .white.opacity(0.7)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 2.5
            )
    }
}

/// Chips que fluyen a varias líneas (para los géneros en la cara trasera).
private struct FlowChips: View {
    let items: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows(), id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { g in
                        Text(g).font(.caption2).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.mihonAccent.opacity(0.45), in: Capsule())
                            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                    }
                }
            }
        }
    }

    // Agrupa de a 2 por fila (sencillo y estable).
    private func rows() -> [[String]] {
        stride(from: 0, to: items.count, by: 2).map { Array(items[$0..<min($0 + 2, items.count)]) }
    }
}
