import SwiftUI

/// Gestión de descargas: ajuste de retención + lista de capítulos descargados (por manga),
/// con borrado individual o total.
struct DownloadsView: View {
    @Bindable private var settings = AppSettings.shared
    private var manager: DownloadManager { .shared }

    var body: some View {
        List {
            Section {
                Picker(selection: $settings.retentionDays) {
                    Text("Nunca").tag(0)
                    Text("7 días").tag(7)
                    Text("30 días").tag(30)
                    Text("90 días").tag(90)
                } label: {
                    Label("Eliminar tras", systemImage: "clock.arrow.circlepath")
                }
            } header: {
                Text("Retención")
            } footer: {
                Text("Las descargas completadas se borran automáticamente pasado este tiempo. "
                     + "Se aplica al abrir la app.")
            }

            let groups = manager.grouped
            if groups.isEmpty {
                Section {
                    ContentUnavailableView("Sin descargas", systemImage: "arrow.down.circle",
                                           description: Text("Descarga capítulos desde el detalle de un manga."))
                }
            } else {
                ForEach(groups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.items) { it in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(it.chapterName).lineLimit(1)
                                    Text(statusText(it)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                statusIcon(it)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    manager.delete(it.sourceId, it.mangaId, it.chapterId)
                                } label: { Label("Eliminar", systemImage: "trash") }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Descargas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !manager.grouped.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) { manager.deleteAll() } label: {
                            Label("Eliminar todo", systemImage: "trash")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
    }

    private func statusText(_ it: DownloadItem) -> String {
        switch it.status {
        case .done: return "Completado · \(it.totalPages) págs."
        case .downloading: return "Descargando \(it.downloadedPages)/\(max(it.totalPages, 1))"
        case .queued: return "En cola"
        case .failed: return "Error al descargar"
        }
    }

    @ViewBuilder private func statusIcon(_ it: DownloadItem) -> some View {
        switch it.status {
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.mihonAccent)
        case .downloading: ProgressView().controlSize(.small)
        case .queued: Image(systemName: "clock").foregroundStyle(.secondary)
        case .failed: Image(systemName: "exclamationmark.circle").foregroundStyle(.red)
        }
    }
}
