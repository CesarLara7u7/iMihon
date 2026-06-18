import SwiftUI

/// Pantalla de detalle. Equivale a `MangaScreen.kt` (Compose).
struct MangaDetailView: View {
    let manga: Manga
    @State private var descriptionExpanded = false

    var body: some View {
        List {
            header
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)

            Section {
                ForEach(manga.chapters) { chapter in
                    NavigationLink(value: chapter) {
                        ChapterRow(chapter: chapter)
                    }
                }
            } header: {
                Text("\(manga.chapters.count) capítulos")
            }
        }
        .listStyle(.plain)
        .navigationTitle(manga.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Chapter.self) { chapter in
            ReaderView(manga: manga, chapter: chapter)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { } label: { Image(systemName: manga.inLibrary ? "heart.fill" : "heart") }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                CoverPlaceholder(title: manga.title)
                    .frame(width: 110, height: 165)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 6) {
                    Text(manga.title).font(.headline)
                    Text(manga.author).font(.subheadline).foregroundStyle(.secondary)
                    Label(manga.status.rawValue, systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(manga.sourceName, systemImage: "globe")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text(manga.description)
                .font(.subheadline)
                .lineLimit(descriptionExpanded ? nil : 3)
                .onTapGesture { withAnimation { descriptionExpanded.toggle() } }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(manga.genres, id: \.self) { genre in
                        Text(genre)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
        }
        .padding()
    }
}

private struct ChapterRow: View {
    let chapter: Chapter

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if chapter.bookmark {
                    Image(systemName: "bookmark.fill").foregroundStyle(Color.mihonAccent).font(.caption)
                }
                Text(chapter.name)
                    .foregroundStyle(chapter.read ? .secondary : .primary)
            }
            HStack(spacing: 8) {
                Text(chapter.dateUpload, style: .date)
                if let scanlator = chapter.scanlator {
                    Text("•"); Text(scanlator)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        MangaDetailView(manga: MockData.library[0])
    }
}
