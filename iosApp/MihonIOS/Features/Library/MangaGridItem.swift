import SwiftUI

/// Celda de portada con badge de no leídos. Equivale a `MangaComfortableGridItem` (Compose).
struct MangaGridItem: View {
    let manga: Manga

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                CoverPlaceholder(title: manga.title)
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if manga.unreadCount > 0 {
                    Text("\(manga.unreadCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.mihonAccent, in: Capsule())
                        .padding(6)
                }
            }
            Text(manga.title)
                .font(.caption)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
