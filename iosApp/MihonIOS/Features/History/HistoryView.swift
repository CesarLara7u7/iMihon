import SwiftUI
import Shared

/// Pestaña Historial: manga leídos recientemente (último capítulo abierto por manga).
struct HistoryView: View {
    @State private var entries: [HistoryEntry] = []

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView {
                        Label("Historial vacío \(Kaomoji.pick(Kaomoji.empty, seed: 0))", systemImage: "clock")
                    } description: {
                        Text("Aquí aparecerán los manga que vayas leyendo.")
                    }
                } else {
                    list
                }
            }
            .themedBackground()
            .navigationTitle("Historial")
            .onAppear { reload() }
        }
    }

    private var list: some View {
        List(entries, id: \.mangaId) { e in
            NavigationLink {
                SourceMangaDetailView(sourceId: e.sourceId, mangaId: e.mangaId,
                                      fallbackTitle: e.mangaTitle, fallbackThumb: e.thumbnailUrl)
            } label: {
                HStack(spacing: 12) {
                    CachedImage(url: URL(string: e.thumbnailUrl ?? "")) {
                        CoverPlaceholder(title: e.mangaTitle)
                    }
                    .scaledToFill()
                    .frame(width: 44, height: 62)
                    .coverCard(cornerRadius: 6)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(e.mangaTitle).font(.subheadline.weight(.medium)).lineLimit(1)
                        HStack(spacing: 6) {
                            Text(e.chapterName)
                            if e.readAt > 0 {
                                Text("•")
                                Text(Date(timeIntervalSince1970: TimeInterval(e.readAt) / 1000), style: .relative)
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .glassListRow()
        }
        .listStyle(.plain)
    }

    private func reload() {
        entries = (try? MockData.bridgeInstance.history()) ?? []
    }
}

#Preview { HistoryView() }
