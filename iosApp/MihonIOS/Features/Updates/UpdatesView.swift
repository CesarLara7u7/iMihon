import SwiftUI
import Shared

/// Pestaña Recientes: últimas actualizaciones. Por defecto solo de los manga en biblioteca;
/// el interruptor (arriba a la derecha) muestra también los que no están en la biblioteca.
struct UpdatesView: View {
    private var store: UpdatesStore { .shared }
    @State private var showAll = false
    @State private var savedOverride: [String: Bool] = [:]

    private var visible: [RecentUpdate] {
        showAll ? store.updates : store.updates.filter { $0.inLibrary }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch store.phase {
                case .loading:
                    SkeletonRows()
                case .failed(let msg):
                    ContentUnavailableView {
                        Label("Error \(Kaomoji.pick(Kaomoji.error, seed: 1))", systemImage: "wifi.slash")
                    } description: { Text(msg) } actions: {
                        Button("Reintentar") { Task { await store.refresh() } }
                    }
                case .ready where visible.isEmpty:
                    ContentUnavailableView {
                        Label("Sin novedades \(Kaomoji.pick(Kaomoji.empty, seed: 2))", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text(showAll ? "No hay actualizaciones recientes." :
                                "Sin novedades en tu biblioteca. Activa el interruptor para ver todas.")
                    }
                default:
                    list
                }
            }
            .themedBackground()
            .navigationTitle("Actualizaciones")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 6) {
                        Text("Global").font(.subheadline).foregroundStyle(.secondary)
                        Toggle("Global", isOn: $showAll)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .labelsHidden()
                    }
                }
            }
            .refreshable { await store.refresh() }   // deslizar de arriba a abajo para refrescar
            .task { await store.loadIfNeeded() }       // usa caché; refresca si pasaron 20 min
        }
    }

    private func isSaved(_ u: RecentUpdate) -> Bool { savedOverride[u.mangaId] ?? u.inLibrary }

    private func toggleSave(_ u: RecentUpdate) {
        let target = !isSaved(u)
        if MockData.setFavorite(sourceId: u.sourceId, mangaId: u.mangaId,
                                title: u.mangaTitle, thumbnail: u.thumbnailUrl, favorite: target) {
            withAnimation(.snappy) { savedOverride[u.mangaId] = target }
        }
    }

    private var list: some View {
        List(visible, id: \.chapterId) { u in
            NavigationLink {
                SourceMangaDetailView(sourceId: u.sourceId, mangaId: u.mangaId,
                                      fallbackTitle: u.mangaTitle, fallbackThumb: u.thumbnailUrl)
            } label: {
                HStack(spacing: 12) {
                    CachedImage(url: URL(string: u.thumbnailUrl ?? "")) {
                        CoverPlaceholder(title: u.mangaTitle)
                    }
                    .scaledToFill()
                    .frame(width: 44, height: 62)
                    .coverCard(cornerRadius: 6)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(u.mangaTitle).font(.subheadline.weight(.medium)).lineLimit(1)
                        HStack(spacing: 6) {
                            Text(u.chapterName)
                            if u.uploadDate > 0 {
                                Text("•")
                                Text(Date(timeIntervalSince1970: TimeInterval(u.uploadDate) / 1000), style: .date)
                            }
                            if isSaved(u) {
                                Text("•"); Image(systemName: "heart.fill").foregroundStyle(Color.mihonAccent)
                            } else {
                                Text("•"); Image(systemName: "plus.circle").foregroundStyle(.tertiary)
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { toggleSave(u) } label: {
                    Label(isSaved(u) ? "Quitar" : "Guardar",
                          systemImage: isSaved(u) ? "heart.slash" : "heart")
                }
                .tint(.mihonAccent)
            }
            .glassListRow()
        }
        .listStyle(.plain)
    }
}

#Preview { UpdatesView() }
