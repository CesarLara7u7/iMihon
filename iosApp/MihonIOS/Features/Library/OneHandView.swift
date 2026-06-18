import SwiftUI
import Shared

/// **Modo una mano**: carrusel de portadas a pantalla completa (estilo Steam Big Picture),
/// pensado para navegar con el pulgar. La portada enfocada se agranda y el botón de abrir queda
/// abajo, al alcance. El fondo es la portada enfocada difuminada.
struct OneHandView: View {
    let items: [BrowseManga]
    @Environment(\.dismiss) private var dismiss
    @State private var focusedId: String?

    private var focused: BrowseManga? {
        items.first { $0.id == focusedId } ?? items.first
    }

    var body: some View {
        // El ancho REAL de pantalla (el GeometryReader dentro del fullScreenCover/NavigationStack
        // reportaba más, por eso el título no se acotaba).
        let screenW = UIScreen.main.bounds.width
        let cardW = screenW * 0.46   // 30% más pequeñas que antes (0.66)
        let cardH = cardW * 1.5
        return NavigationStack {
            ZStack {
                background
                VStack(spacing: 0) {
                    header(width: screenW)
                    Spacer(minLength: 0)                 // empuja la portada hacia abajo
                    carousel(cardW: cardW, cardH: cardH, containerW: screenW)
                    Spacer().frame(height: 18)           // hueco corto con el botón
                    footer(width: screenW)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear { if focusedId == nil { focusedId = items.first?.id } }
    }

    private var background: some View {
        ZStack {
            if let url = focused?.thumbnailUrl, let u = URL(string: url) {
                CachedImage(url: u) { Color.black }
                    .scaledToFill()
                    .blur(radius: 45)
                    .opacity(0.55)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.4), value: focusedId)
            }
            Color.black.opacity(0.45).ignoresSafeArea()
        }
    }

    private func header(width: CGFloat) -> some View {
        HStack {
            Button { dismiss() } label: {   // tocar "Una mano" sale del modo
                Label("Una mano", systemImage: "hand.point.up.left.fill")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.85))
            }
            .buttonStyle(.plain)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle())
            }
        }
        .frame(width: width)
        .padding(.horizontal).padding(.top, 8)
    }

    private func carousel(cardW: CGFloat, cardH: CGFloat, containerW: CGFloat) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 30) {
                ForEach(items, id: \.id) { manga in
                    NavigationLink { detail(manga) } label: { card(manga, width: cardW, height: cardH) }
                        .buttonStyle(.plain)
                        // Vecinas más pequeñas y tenues ⇒ el asomo se ve como una previa limpia,
                        // no como una portada "cortada".
                        .scrollTransition { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.74)
                                .opacity(phase.isIdentity ? 1 : 0.4)
                        }
                        .id(manga.id)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, Swift.max(0, (containerW - cardW) / 2), for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $focusedId, anchor: .center)
        .scrollIndicators(.hidden)
        // Ancho FIJO: evita que el ScrollView ensanche el layout y desborde título/botón.
        .frame(width: containerW, height: cardH + 30)
        .onChange(of: focusedId) { _, _ in
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }

    private func card(_ manga: BrowseManga, width: CGFloat, height: CGFloat) -> some View {
        Color.clear
            .frame(width: width, height: height)
            .overlay {
                CachedImage(url: URL(string: manga.thumbnailUrl ?? "")) {
                    CoverPlaceholder(title: manga.title)
                }
                .scaledToFill()
            }
            .coverCard(cornerRadius: 16)
            .shadow(color: .black.opacity(0.55), radius: 18, y: 12)
    }

    private func footer(width: CGFloat) -> some View {
        VStack(spacing: 14) {
            Text(focused?.title ?? "")
                .font(.title3.bold()).foregroundStyle(.white)
                .multilineTextAlignment(.center).lineLimit(2)
                .frame(width: width - 48)                 // ancho EXPLÍCITO ⇒ envuelve, no desborda
                .animation(.easeInOut(duration: 0.2), value: focusedId)

            if let manga = focused {
                NavigationLink { detail(manga) } label: {
                    Label("Abrir", systemImage: "book.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .glassProminentButton().tint(.mihonAccent)
                .frame(width: width * 0.56)   // ~30% más angosto
            }
        }
        .frame(width: width)
        .padding(.bottom, 28).padding(.top, 8)
    }

    private func detail(_ manga: BrowseManga) -> some View {
        SourceMangaDetailView(sourceId: manga.sourceId, mangaId: manga.id,
                              fallbackTitle: manga.title, fallbackThumb: manga.thumbnailUrl)
    }
}
