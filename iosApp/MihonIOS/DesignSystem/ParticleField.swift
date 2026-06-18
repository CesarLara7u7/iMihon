import SwiftUI

/// Campo de partículas ambiental: puntos tenues tintados con el acento que flotan hacia arriba
/// con un leve vaivén y se desvanecen. Dibujado con `Canvas` + `TimelineView` para rendimiento.
struct ParticleField: View {
    var count: Int = 22
    var color: Color = .mihonAccent

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let cycle = size.height + 80
                for i in 0..<count {
                    let xFrac = rnd(i, 12.9898)
                    let speed = 12 + rnd(i, 78.233) * 26                  // px/s
                    let radius = 1.4 + rnd(i, 3.71) * 2.6
                    let phase = rnd(i, 5.17) * 1000
                    let swayAmp = 8 + rnd(i, 9.21) * 18

                    // Recorrido hacia arriba (bucle).
                    let progress = (now * speed + phase).truncatingRemainder(dividingBy: cycle)
                    let y = size.height + 40 - progress
                    let x = xFrac * size.width + sin(now * 0.5 + Double(i)) * swayAmp

                    // Se desvanece en los extremos (pico a la mitad del recorrido).
                    let fade = sin(.pi * progress / cycle)
                    let opacity = max(0, min(0.4, 0.4 * fade))

                    let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(color.opacity(opacity)))
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Pseudoaleatorio determinista por índice (0…1), estable entre fotogramas.
    private func rnd(_ i: Int, _ salt: Double) -> Double {
        let v = sin((Double(i) + 1) * salt) * 43758.5453
        return v - floor(v)
    }
}
