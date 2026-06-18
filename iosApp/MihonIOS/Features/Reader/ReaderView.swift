import SwiftUI

/// Lector. Equivale a `ReaderActivity` + viewers (PagerViewer/WebtoonViewer) en Mihon.
/// Aquí solo modo paginado con placeholders. El zoom/subsampling real llegará después.
struct ReaderView: View {
    @State private var viewModel: ReaderViewModel

    init(manga: Manga, chapter: Chapter) {
        _viewModel = State(initialValue: ReaderViewModel(manga: manga, chapter: chapter))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $viewModel.currentPage) {
                ForEach(0..<viewModel.pageCount, id: \.self) { page in
                    PagePlaceholder(page: page + 1, chapter: viewModel.chapter.name)
                        .tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onTapGesture { withAnimation { viewModel.showControls.toggle() } }

            if viewModel.showControls {
                controls
            }
        }
        .navigationBarBackButtonHidden(!viewModel.showControls)
        .toolbar(viewModel.showControls ? .visible : .hidden, for: .navigationBar)
        .navigationTitle(viewModel.chapter.name)
        .navigationBarTitleDisplayMode(.inline)
        .statusBarHidden(!viewModel.showControls)
    }

    private var controls: some View {
        VStack {
            Spacer()
            HStack {
                Text(viewModel.manga.title).font(.caption).lineLimit(1)
                Spacer()
                Text(viewModel.progressText).font(.caption.monospacedDigit())
            }
            .padding()
            .foregroundStyle(.white)
            .background(.black.opacity(0.6))
        }
        .transition(.opacity)
    }
}

private struct PagePlaceholder: View {
    let page: Int
    let chapter: String

    var body: some View {
        ZStack {
            Color.deterministic(from: "\(chapter)-\(page)")
            VStack {
                Image(systemName: "photo").font(.largeTitle)
                Text("Página \(page)").font(.headline)
            }
            .foregroundStyle(.white.opacity(0.85))
        }
    }
}

#Preview {
    NavigationStack {
        ReaderView(manga: MockData.library[0], chapter: MockData.library[0].chapters[0])
    }
}
