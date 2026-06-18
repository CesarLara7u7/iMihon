import SwiftUI

/// Controles de preferencias de lectura, compartidos por el panel del lector (por manga)
/// y la pantalla de Preferencias (valores globales por defecto). Va dentro de un `Form`.
struct ReadingControls: View {
    @Binding var mode: Int          // 0 paginado, 1 webtoon
    @Binding var direction: Int     // 0 izq→der, 1 der→izq (RTL)
    @Binding var colorFilter: Int   // 0 ninguno, 1 B/N, 2 sepia, 3 sepia suave
    @Binding var intensity: Double
    @Binding var doublePage: Bool

    var body: some View {
        Section("Modo") {
            Picker("Modo", selection: $mode) {
                Text("Paginado").tag(0); Text("Webtoon").tag(1)
            }.pickerStyle(.segmented)
        }

        if mode == 0 {
            Section("Dirección") {
                Picker("Dirección", selection: $direction) {
                    Text("Izq → Der").tag(0); Text("Der → Izq").tag(1)
                }.pickerStyle(.segmented)
            }
            Section {
                Toggle(isOn: $doublePage) {
                    Label("Páginas dobles", systemImage: "book.pages")
                }
            } footer: {
                Text("Las páginas anchas (spreads) se acercan para leerlas como 2 mitades.")
            }
        }

        Section("Filtro de color") {
            Picker("Filtro", selection: $colorFilter) {
                Text("Ninguno").tag(0); Text("B/N").tag(1)
                Text("Sepia").tag(2); Text("Sepia suave").tag(3)
            }.pickerStyle(.segmented)
            if colorFilter != 0 {
                VStack(alignment: .leading) {
                    Text("Intensidad").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $intensity, in: 0...1)
                }
            }
        }
    }
}
