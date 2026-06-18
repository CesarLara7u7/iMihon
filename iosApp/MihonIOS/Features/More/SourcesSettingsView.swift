import SwiftUI
import Shared

/// Nombre legible de un código de idioma de fuente (compartido por Explorar y Fuentes).
func mangaLangName(_ code: String) -> String {
    switch code {
    case "es": return "Español"
    case "es-419": return "Español (LatAm)"
    case "en": return "English"
    case "pt-br": return "Português (BR)"
    case "pt": return "Português"
    case "fr": return "Français"
    case "it": return "Italiano"
    case "de": return "Deutsch"
    case "ru": return "Русский"
    case "id": return "Indonesia"
    case "ja": return "日本語"
    case "ko": return "한국어"
    case "zh": return "中文"
    case "ar": return "العربية"
    case "th": return "ไทย"
    case "vi": return "Tiếng Việt"
    case "all": return "Todos"
    default: return code.uppercased()
    }
}

/// **Fuentes**: cada fuente es un desplegable con un interruptor maestro (toda la fuente) y los
/// idiomas dentro. Las marcadas +18 piden confirmación de edad antes de activarse.
struct SourcesSettingsView: View {
    @Bindable private var settings = AppSettings.shared
    @State private var sources: [SourceInfo] = []
    @State private var showAgeGate = false
    @State private var ageGateAction: (() -> Void)?
    @State private var showDefaultTip = false

    private struct Group: Identifiable {
        let name: String
        let isNsfw: Bool
        let items: [SourceInfo]
        var id: String { name }
    }

    private var grouped: [Group] {
        Dictionary(grouping: sources, by: { $0.name })
            .map { Group(name: $0.key, isNsfw: $0.value.contains { $0.isNsfw },
                         items: $0.value.sorted { mangaLangName($0.lang) < mangaLangName($1.lang) }) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        Form {
            Section {} footer: {
                Text("Activa una fuente con su interruptor: al activarla se despliegan sus idiomas "
                     + "para ajustarlos. Las marcadas 18+ piden confirmación de edad.")
            }
            ForEach(grouped) { group in
                Section {
                    // El interruptor maestro activa la fuente Y despliega/contrae sus idiomas.
                    Toggle(isOn: masterBinding(group)) {
                        HStack(spacing: 8) {
                            Text(group.name).font(.headline)
                            if group.isNsfw { nsfwBadge }
                            Spacer()
                            Text(enabledCount(group)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if isActive(group) {
                        ForEach(group.items, id: \.id) { src in
                            HStack(spacing: 10) {
                                Button { setDefault(src) } label: {
                                    Image(systemName: settings.defaultSourceId == src.id ? "star.fill" : "star")
                                        .foregroundStyle(settings.defaultSourceId == src.id ? .yellow : .secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Marcar como predeterminada")
                                Toggle(isOn: langBinding(src)) { Text(mangaLangName(src.lang)) }
                            }
                            .padding(.leading, 12)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: isActive(group))
            }
        }
        .navigationTitle("Fuentes")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { sources = MockData.bridgeInstance.sources() }
        .alert("Contenido para adultos (18+)", isPresented: $showAgeGate) {
            Button("Soy mayor de 18", role: .destructive) { ageGateAction?(); ageGateAction = nil }
            Button("Cancelar", role: .cancel) { ageGateAction = nil }
        } message: {
            Text("Esta fuente puede contener material explícito. Confirma que eres mayor de edad para activarla.")
        }
        .alert("Fuente predeterminada", isPresented: $showDefaultTip) {
            Button("OK") {}
            Button("No mostrar de nuevo") { settings.defaultSourceTipDismissed = true }
        } message: {
            Text("Esta fuente se usará por defecto en Explorar y para mostrar las actualizaciones globales.")
        }
    }

    /// Marca la fuente como predeterminada (la habilita si estaba apagada) y muestra el aviso.
    private func setDefault(_ src: SourceInfo) {
        settings.defaultSourceId = src.id
        settings.disabledSources.remove(src.id)
        if !settings.defaultSourceTipDismissed { showDefaultTip = true }
    }

    private var nsfwBadge: some View {
        Text("18+").font(.caption2.bold()).foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.red, in: Capsule())
    }

    private func enabledCount(_ g: Group) -> String {
        let on = g.items.filter { settings.sourceEnabled($0.id) }.count
        return "\(on)/\(g.items.count)"
    }

    /// Fuente "activa" = al menos un idioma habilitado (controla el desplegado).
    private func isActive(_ g: Group) -> Bool { g.items.contains { settings.sourceEnabled($0.id) } }

    private func masterBinding(_ g: Group) -> Binding<Bool> {
        Binding(
            get: { isActive(g) },
            set: { on in
                if on {
                    let enableAll = { withAnimation(.easeInOut(duration: 0.22)) {
                        g.items.forEach { settings.disabledSources.remove($0.id) } } }
                    if g.isNsfw { ageGateAction = enableAll; showAgeGate = true } else { enableAll() }
                } else {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        g.items.forEach { settings.disabledSources.insert($0.id) }
                    }
                }
            }
        )
    }

    private func langBinding(_ src: SourceInfo) -> Binding<Bool> {
        Binding(
            get: { settings.sourceEnabled(src.id) },
            set: { on in
                if on {
                    if src.isNsfw { ageGateAction = { settings.disabledSources.remove(src.id) }; showAgeGate = true }
                    else { settings.disabledSources.remove(src.id) }
                } else {
                    settings.disabledSources.insert(src.id)
                }
            }
        )
    }
}

#Preview { NavigationStack { SourcesSettingsView() } }
