import SwiftUI

/// Personalización visual: color de énfasis, tema de fondo (degradados) y transparencia del
/// cristal. Cambia la experiencia de toda la app en vivo (acento dinámico, fondos temáticos).
struct PersonalizationView: View {
    @Bindable private var settings = AppSettings.shared

    /// Paleta de acentos sugeridos (hex RRGGBB).
    private let presets = ["6166F2", "2563EB", "0EA5E9", "14B8A6", "22C55E",
                           "EAB308", "F97316", "EF4444", "EC4899", "A855F7"]

    private let swatchColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    /// Emojis para el patrón de fondo (estilo Telegram). "" = sin patrón.
    private let patterns = ["", "📚", "⭐️", "🌙", "🌸", "❤️", "🎴", "🔥", "🍥", "👾", "🐉", "🌊"]

    var body: some View {
        Form {
            Section("Apariencia") {
                Picker(selection: $settings.appearance) {
                    Text("Sistema").tag(0)
                    Text("Claro").tag(1)
                    Text("Oscuro").tag(2)
                } label: { Label("Tema", systemImage: "circle.lefthalf.filled") }
                .pickerStyle(.segmented)

                Toggle(isOn: $settings.libraryCoverBackground) {
                    Label("Fondo con portada", systemImage: "photo")
                }
                if settings.libraryCoverBackground {
                    Toggle(isOn: $settings.backgroundGyro) {
                        Label("Mover fondo con giroscopio", systemImage: "gyroscope")
                    }
                }
                Toggle(isOn: $settings.cardGyro) {
                    Label("Giroscopio en portada", systemImage: "rotate.3d")
                }
                Toggle(isOn: $settings.particles) {
                    Label("Partículas de fondo", systemImage: "sparkles")
                }
            }

            Section {
                preview
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("Color de énfasis") {
                LazyVGrid(columns: swatchColumns, spacing: 14) {
                    ForEach(presets, id: \.self) { hex in
                        accentSwatch(hex)
                    }
                }
                .padding(.vertical, 6)
                ColorPicker("Color personalizado", selection: $settings.accentColor, supportsOpacity: false)
            }

            Section("Fondo") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(0..<AppTheme.names.count, id: \.self) { themeSwatch($0) }
                    }
                    .padding(.vertical, 6)
                }
                .scrollClipDisabled()
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(patterns, id: \.self) { patternSwatch($0) }
                    }
                    .padding(.vertical, 4)
                }
                .scrollClipDisabled()
            } header: {
                Text("Patrón")
            } footer: {
                Text("Un emoji repetido y tenue de fondo, al estilo de los chats de Telegram.")
            }

            Section {
                Toggle(isOn: $settings.clearGlass) {
                    Label("Cristal más transparente", systemImage: "circle.lefthalf.filled")
                }
            } footer: {
                Text("Aumenta la transparencia de las barras y botones de cristal.")
            }
        }
        .navigationTitle("Personalización")
        .navigationBarTitleDisplayMode(.inline)
        .themedBackground()
        .animation(.snappy, value: settings.accentHex)
        .animation(.snappy, value: settings.backgroundStyle)
        .animation(.snappy, value: settings.clearGlass)
        .animation(.snappy, value: settings.patternEmoji)
    }

    // MARK: - Vista previa

    private var preview: some View {
        ZStack {
            AppTheme.gradient(settings.backgroundStyle, accent: settings.accentColor)
            if !settings.patternEmoji.isEmpty { EmojiPattern(emoji: settings.patternEmoji) }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "books.vertical.fill")
                        .font(.title2).foregroundStyle(settings.accentColor)
                    VStack(alignment: .leading) {
                        Text("Tu biblioteca").font(.headline)
                        Text("Vista previa del tema").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "heart.fill").foregroundStyle(.white)
                        .padding(7).background(settings.accentColor, in: Circle())
                }
                HStack {
                    Button("Continuar") {}
                        .glassProminentButton().tint(settings.accentColor)
                    Spacer()
                    Text("AaBb").font(.subheadline.bold()).foregroundStyle(settings.accentColor)
                }
            }
            .padding()
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(settings.accentColor.opacity(0.45), lineWidth: 1))
        .shadow(color: settings.accentColor.opacity(0.30), radius: 14, y: 7)
        .padding()
    }

    // MARK: - Swatches

    private func accentSwatch(_ hex: String) -> some View {
        let isSel = settings.accentHex.caseInsensitiveCompare(hex) == .orderedSame
        return Circle()
            .fill(Color(hex: hex))
            .frame(width: 36, height: 36)
            .overlay {
                if isSel { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) }
            }
            .overlay {
                Circle().stroke(.primary.opacity(isSel ? 0.9 : 0), lineWidth: 2).padding(-3)
            }
            .shadow(color: Color(hex: hex).opacity(0.5), radius: isSel ? 5 : 2, y: 1)
            .scaleEffect(isSel ? 1.12 : 1)
            .onTapGesture { withAnimation(.snappy) { settings.accentHex = hex } }
    }

    private func patternSwatch(_ emoji: String) -> some View {
        let isSel = settings.patternEmoji == emoji
        return ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
                .frame(width: 52, height: 52)
            if emoji.isEmpty {
                Image(systemName: "nosign").foregroundStyle(.secondary)
            } else {
                Text(emoji).font(.title2)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSel ? settings.accentColor : Color.primary.opacity(0.12), lineWidth: isSel ? 3 : 1)
        }
        .scaleEffect(isSel ? 1.08 : 1)
        .onTapGesture { withAnimation(.snappy) { settings.patternEmoji = emoji } }
    }

    private func themeSwatch(_ i: Int) -> some View {
        let isSel = settings.backgroundStyle == i
        return VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.clear)
                .frame(width: 62, height: 84)
                .background { AppTheme.gradient(i, accent: settings.accentColor) }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSel ? settings.accentColor : Color.primary.opacity(0.12),
                                lineWidth: isSel ? 3 : 1)
                }
                .shadow(radius: isSel ? 5 : 0, y: 2)
            Text(AppTheme.names[i])
                .font(.caption2)
                .foregroundStyle(isSel ? Color.primary : .secondary)
        }
        .scaleEffect(isSel ? 1.04 : 1)
        .onTapGesture { withAnimation(.snappy) { settings.backgroundStyle = i } }
    }
}

#Preview { NavigationStack { PersonalizationView() } }
