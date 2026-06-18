import SwiftUI
import Shared

/// Pestaña Explorar. Arquitectura sin servidor: lista las fuentes nativas (MangaDex…) y
/// muestra el catálogo consultando la API de la fuente directamente.
struct BrowseView: View {
    @State private var sources: [SourceInfo] = []
    @State private var selectedSourceId: String?
    @State private var catalog: [BrowseManga] = []
    @State private var phase: Phase = .idle
    @State private var query = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var savedOverride: [String: Bool] = [:]
    // Filtros del catálogo.
    @State private var sort = 0                       // 0 popular, 1 actualizados, 2 puntuados
    @State private var selectedGenres: Set<String> = []
    @State private var genres: [SourceGenre] = []
    @State private var showFilters = false
    // Búsqueda global (streaming, sobrevive a la navegación).
    @State private var searchStore = SearchStore.shared
    @Bindable private var settings = AppSettings.shared

    enum Phase: Equatable { case idle, loadingManga, ready, failed(String) }

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]
    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var filtersActive: Bool { sort != 0 || !selectedGenres.isEmpty }

    var body: some View {
        NavigationStack {
            Group {
                if isSearching {
                    searchResults
                } else if case .failed(let msg) = phase {
                    ContentUnavailableView {
                        Label("Error \(Kaomoji.pick(Kaomoji.error, seed: 2))", systemImage: "wifi.slash")
                    } description: { Text(msg) } actions: {
                        Button("Reintentar") { Task { await loadCatalog() } }
                    }
                } else {
                    catalogGrid
                }
            }
            .themedBackground()
            .navigationTitle("Explorar")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !isSearching {
                        Button { showFilters = true } label: {
                            Image(systemName: filtersActive
                                  ? "line.3.horizontal.decrease.circle.fill"
                                  : "line.3.horizontal.decrease.circle")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { sourceMenu }
            }
            .searchable(text: $query, prompt: "Buscar en todas las fuentes")
            .onSubmit(of: .search) { searchTask?.cancel(); runGlobalSearch() }
            .onChange(of: query) { _, newValue in
                searchTask?.cancel()
                if newValue.trimmingCharacters(in: .whitespaces).isEmpty { searchStore.clear(); return }
                // Debounce: busca 1s después de dejar de escribir.
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if !Task.isCancelled { runGlobalSearch() }
                }
            }
            .sheet(isPresented: $showFilters) {
                BrowseFiltersSheet(sort: $sort, selected: $selectedGenres, genres: genres,
                                   supportsRating: selectedSource?.supportsRating ?? false,
                                   onApply: { Task { await loadCatalog() } })
                    .presentationDetents([.medium, .large])
            }
            .task { if sources.isEmpty { loadSources() } else { revalidateSelection() } }
            // Si cambia la fuente predeterminada (estrella) en Preferencias, Explorar la adopta.
            .onChange(of: settings.defaultSourceId) { _, newId in
                guard !newId.isEmpty, newId != selectedSourceId,
                      let src = enabledSources.first(where: { $0.id == newId }) else { return }
                Task { await select(src) }
            }
        }
    }

    // Catálogo de la fuente seleccionada (con orden/géneros aplicados).
    private var catalogGrid: some View {
        ScrollView {
            if phase == .loadingManga {
                LoadingState(text: "Cargando catálogo…").padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(catalog, id: \.compositeKey) { mangaCell($0) }
                }
                .padding(.horizontal)
            }
        }
    }

    // Resultados de búsqueda GLOBAL en streaming: cada fuente aparece en cuanto responde.
    private var searchResults: some View {
        ScrollView {
            if searchStore.groups.isEmpty {
                if searchStore.phase == .searching {
                    SearchSkeleton()        // esqueleto mientras no hay nada todavía
                } else {
                    ContentUnavailableView("Sin resultados \(Kaomoji.pick(Kaomoji.empty, seed: 3))",
                                           systemImage: "magnifyingglass")
                        .padding(.top, 60)
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(searchStore.groups, id: \.sourceId) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(group.sourceName) (\(langName(group.lang)))")
                                .font(.headline).foregroundStyle(Color.mihonAccentText)
                                .padding(.horizontal)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 12) {
                                    ForEach(group.manga, id: \.compositeKey) { mangaCell($0).frame(width: 116) }
                                }
                                .padding(.horizontal)
                            }
                            .scrollClipDisabled()
                        }
                    }
                    if searchStore.phase == .searching {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Buscando en más fuentes…").font(.footnote).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                }
                .padding(.vertical)
            }
        }
    }

    private func mangaCell(_ manga: BrowseManga) -> some View {
        let saved = savedOverride["\(manga.sourceId)|\(manga.id)"] ?? manga.inLibrary
        return NavigationLink {
            SourceMangaDetailView(sourceId: manga.sourceId, mangaId: manga.id,
                                  fallbackTitle: manga.title, fallbackThumb: manga.thumbnailUrl)
        } label: {
            BrowseCoverItem(manga: manga)
        }
        .buttonStyle(CardButtonStyle())
        .overlay(alignment: .topTrailing) {
            CoverSaveButton(saved: saved) { toggleSave(manga, saved: saved) }.padding(6)
        }
    }

    /// Selector de fuentes en cascada: nivel 1 = fuente, nivel 2 = idioma (submenú).
    /// Escala a N fuentes sin desplazamiento horizontal.
    private var sourceMenu: some View {
        Menu {
            ForEach(groupedSources, id: \.name) { group in
                if group.items.count == 1, let only = group.items.first {
                    sourceButton(only, title: only.name)
                } else {
                    Menu(group.name) {
                        ForEach(group.items, id: \.id) { source in
                            sourceButton(source, title: langName(source.lang))
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "books.vertical")
                Text(selectedSource.map { "\($0.name) · \(langName($0.lang))" } ?? "Fuente")
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.subheadline)
        }
    }

    private func sourceButton(_ source: SourceInfo, title: String) -> some View {
        Button {
            Task { await select(source) }
        } label: {
            if selectedSourceId == source.id {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private var selectedSource: SourceInfo? { sources.first { $0.id == selectedSourceId } }

    /// Fuentes HABILITADAS agrupadas por nombre (cada nombre puede tener varios idiomas).
    private var groupedSources: [(name: String, items: [SourceInfo])] {
        Dictionary(grouping: enabledSources, by: { $0.name })
            .map { (name: $0.key, items: $0.value.sorted { $0.lang < $1.lang }) }
            .sorted { $0.name < $1.name }
    }

    private func langName(_ code: String) -> String { mangaLangName(code) }

    /// Solo las fuentes habilitadas por el usuario (Preferencias → Fuentes).
    private var enabledSources: [SourceInfo] {
        sources.filter { AppSettings.shared.sourceEnabled($0.id) }
    }

    // MARK: - Carga

    private func loadSources() {
        sources = MockData.bridgeInstance.sources()
        // Preferencia: fuente predeterminada (estrella) → MangaDex español → primera habilitada.
        let enabled = enabledSources
        let preferred = AppSettings.shared.defaultSourceId
        if let first = enabled.first(where: { $0.id == preferred })
            ?? enabled.first(where: { $0.id == "mangadex-es" }) ?? enabled.first {
            Task { await select(first) }
        }
    }

    /// Si la fuente seleccionada quedó deshabilitada (cambios en Preferencias), elige otra.
    private func revalidateSelection() {
        if let id = selectedSourceId, AppSettings.shared.sourceEnabled(id) { return }
        if let first = enabledSources.first { Task { await select(first) } }
    }

    private func select(_ source: SourceInfo) async {
        selectedSourceId = source.id
        query = ""
        sort = 0
        selectedGenres = []
        await loadCatalog()
        await loadGenres()
    }

    private func loadCatalog() async {
        guard let id = selectedSourceId else { return }
        phase = .loadingManga
        do {
            catalog = try await MockData.bridgeInstance.browse(
                sourceId: id, sort: Int32(sort), genreIds: Array(selectedGenres), page: 1)
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func loadGenres() async {
        guard let id = selectedSourceId else { return }
        genres = (try? await MockData.bridgeInstance.sourceGenres(sourceId: id)) ?? []
    }

    /// Búsqueda GLOBAL en streaming (resultados por fuente conforme llegan).
    private func runGlobalSearch() {
        searchStore.run(query: query, sourceIds: enabledSources.map { $0.id })
    }

    /// Guarda/quita el manga de la biblioteca desde la portada, sin abrir el detalle.
    private func toggleSave(_ manga: BrowseManga, saved: Bool) {
        let target = !saved
        if MockData.setFavorite(sourceId: manga.sourceId, mangaId: manga.id,
                                title: manga.title, thumbnail: manga.thumbnailUrl, favorite: target) {
            withAnimation(.snappy) { savedOverride["\(manga.sourceId)|\(manga.id)"] = target }
        }
    }
}

/// Esqueleto de la búsqueda global: imita el diseño de resultados (secciones por fuente con
/// una fila horizontal de portadas) mientras aún no llega ningún resultado.
private struct SearchSkeleton: View {
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 22) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 150, height: 18)
                        .padding(.horizontal)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(0..<4, id: \.self) { _ in
                                VStack(alignment: .leading, spacing: 6) {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.primary.opacity(0.08))
                                        .frame(width: 116, height: 164)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.primary.opacity(0.08))
                                        .frame(width: 90, height: 12)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .scrollClipDisabled()
                    .disabled(true)
                }
            }
        }
        .padding(.vertical)
        .shimmering()
    }
}

/// Hoja de filtros del catálogo: orden + géneros.
private struct BrowseFiltersSheet: View {
    @Binding var sort: Int
    @Binding var selected: Set<String>
    let genres: [SourceGenre]
    let supportsRating: Bool
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Ordenar por") {
                    Picker("Orden", selection: $sort) {
                        Text("Popularidad").tag(0)
                        Text("Actualizados").tag(1)
                        if supportsRating { Text("Mejor puntuados").tag(2) }
                    }
                    .pickerStyle(.inline).labelsHidden()
                }
                Section("Géneros") {
                    if genres.isEmpty {
                        Text("Sin géneros disponibles").foregroundStyle(.secondary)
                    } else {
                        ForEach(genres, id: \.id) { g in
                            Button {
                                if selected.contains(g.id) { selected.remove(g.id) } else { selected.insert(g.id) }
                            } label: {
                                HStack {
                                    Text(g.name).foregroundStyle(.primary)
                                    Spacer()
                                    if selected.contains(g.id) {
                                        Image(systemName: "checkmark").foregroundStyle(Color.mihonAccent)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filtros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Limpiar") { sort = 0; selected = [] }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aplicar") { onApply(); dismiss() }
                }
            }
        }
    }
}

/// Celda de portada del catálogo, con carga de imagen real.
struct BrowseCoverItem: View {
    let manga: BrowseManga

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay {
                    CachedImage(url: URL(string: manga.thumbnailUrl ?? "")) {
                        CoverPlaceholder(title: manga.title)
                    }
                    .scaledToFill()
                }
                .coverCard()
            Text(manga.title)
                .font(.caption).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Botón circular para guardar/quitar de la biblioteca, superpuesto en una portada.
struct CoverSaveButton: View {
    let saved: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label.frame(width: 40, height: 40).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .shadow(radius: 2, y: 1)
    }

    private var icon: some View {
        Image(systemName: saved ? "heart.fill" : "heart")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(7)
    }

    @ViewBuilder private var label: some View {
        if saved {
            icon.background(Color.mihonAccent, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.5))
        } else {
            icon.liquidGlass(in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.5))
        }
    }
}

#Preview { BrowseView() }
