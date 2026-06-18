import SwiftUI

/// Pestaña Preferencias: encabeza con las preferencias de lectura GLOBALES (incógnito +
/// modo/dirección/filtro/páginas dobles por defecto) y agrupa el resto de ajustes y utilidades.
/// (iOS limita la barra a 5 pestañas, por eso este hub reúne lo que antes era "Más".)
struct MoreView: View {
    @State private var downloadedOnly = false
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $settings.incognito) {
                        Label("Modo incógnito", systemImage: "eyeglasses")
                    }
                    Toggle(isOn: $downloadedOnly) {
                        Label("Solo descargados", systemImage: "arrow.down.circle")
                    }
                } footer: {
                    if settings.incognito {
                        Text("El lector no guardará historial ni progreso mientras esté activo.")
                    }
                }

                Section("Ajustes") {
                    NavigationLink {
                        ReadingSettingsView()
                    } label: { Label("Lectura", systemImage: "book") }
                    NavigationLink {
                        PersonalizationView()
                    } label: { Label("Personalización", systemImage: "paintpalette") }
                    NavigationLink {
                        SourcesSettingsView()
                    } label: { Label("Fuentes", systemImage: "globe") }
                    NavigationLink {
                        DownloadsView()
                    } label: { Label("Descargas", systemImage: "arrow.down.circle") }
                    NavigationLink {
                        SettingsPlaceholder(title: "Seguimiento")
                    } label: { Label("Seguimiento", systemImage: "checkmark.circle") }
                }

                Section("Datos") {
                    NavigationLink {
                        SettingsPlaceholder(title: "Copia de seguridad")
                    } label: { Label("Copia de seguridad", systemImage: "externaldrive") }
                }

                Section {
                    NavigationLink {
                        SettingsPlaceholder(title: "Acerca de")
                    } label: { Label("Acerca de", systemImage: "info.circle") }
                }
            }
            .themedBackground()
            .navigationTitle("Preferencias")
        }
    }
}

private struct SettingsPlaceholder: View {
    let title: String
    var body: some View {
        ContentUnavailableView(title, systemImage: "gearshape", description: Text("Pendiente de implementar"))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview { MoreView() }
