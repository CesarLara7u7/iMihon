import SwiftUI

/// Ajustes de **Lectura** (valores por defecto del lector): modo, dirección, páginas dobles,
/// filtro de color + intensidad, y los mensajes de descanso del final del capítulo.
struct ReadingSettingsView: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            // Modo / dirección / páginas dobles / filtro de color + intensidad.
            ReadingControls(
                mode: $settings.defaultMode,
                direction: $settings.defaultDirection,
                colorFilter: $settings.defaultColorFilter,
                intensity: $settings.defaultIntensity,
                doublePage: $settings.doublePageDefault
            )

            Section {
                Toggle(isOn: $settings.restMessages) {
                    Label("Mensaje de descanso al final", systemImage: "moon.zzz")
                }
            } footer: {
                Text("Muestra un mensaje que invita a descansar o continuar en la página final "
                     + "del capítulo. Los valores de arriba se aplican a manga sin preferencias "
                     + "propias; dentro del lector cada manga puede ajustarlas por separado.")
            }
        }
        .navigationTitle("Lectura")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview { NavigationStack { ReadingSettingsView() } }
