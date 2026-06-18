import SwiftUI
import Shared

/// Pestaña Biblioteca. Sin servidor: muestra los favoritos LOCALES (SQLite) organizados en
/// **estanterías** (una por categoría + "Sin categoría"), estilo Netflix. Al buscar, rejilla plana.
struct LibraryView: View {
    @State private var shelves: [Shelf] = []
    @State private var allFavorites: [BrowseManga] = []
    @State private var query = ""
    @State private var showCategories = false
    @Bindable private var settings = AppSettings.shared
    /// Portada del último manga leído, para el fondo difuminado en B/N.
    @State private var lastCoverURL: String?
    /// Claves "source|manga" que solo viven en estanterías privadas (se ocultan del buscador).
    @State private var hiddenKeys: Set<String> = []
    /// Estantería privada revelada al escribir su palabra mágica exacta.
    @State private var revealed: Shelf?
    /// Color dinámico extraído de la portada del último leído (tiñe el fondo).
    @State private var dynamicColor: Color?
    @State private var hasPrivate = false
    @State private var unlockedPrivate = false
    /// Manga cuya tarjeta coleccionable se muestra al mantener presionado.
    @State private var cardManga: BrowseManga?
    @State private var privateShelvesList: [Shelf] = []
    /// Giroscopio para el desplazamiento suave del fondo.
    @State private var bgMotion = MotionManager()
    /// Revelado de privadas al estilo Telegram: dos "tirones" hacia abajo seguidos en el tope.
    @State private var overscrollArmed = true
    @State private var pullCount = 0

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    private var filtered: [BrowseManga] {
        let base = allFavorites.filter { !hiddenKeys.contains("\($0.sourceId)|\($0.id)") }
        guard !query.isEmpty else { return base }
        return base.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if allFavorites.isEmpty {
                    ContentUnavailableView {
                        Label("Biblioteca vacía", systemImage: "books.vertical")
                    } description: {
                        Text("Añade manga desde la pestaña Explorar.")
                    }
                } else if let revealed {
                    revealedShelf(revealed)
                } else if !query.isEmpty {
                    grid
                } else {
                    shelvesList
                }
            }
            .background { libraryBackground }
            .overlay {
                // Mantener presionada una portada muestra su tarjeta coleccionable (como en el detalle).
                if let m = cardManga {
                    CollectibleCardView(
                        imageURL: m.thumbnailUrl, title: m.title, author: nil, status: nil, genres: [],
                        onClose: { withAnimation(.easeInOut(duration: 0.2)) { cardManga = nil } }
                    )
                    .transition(.opacity)
                }
            }
            .navigationTitle("Biblioteca")
            .searchable(text: $query, prompt: "Buscar en la biblioteca")
            .onChange(of: query) { _, q in
                let word = q.trimmingCharacters(in: .whitespaces)
                // Palabra mágica: revela su estantería privada (coincidencia exacta).
                revealed = word.isEmpty ? nil : (try? MockData.bridgeInstance.privateShelf(word: word)) ?? nil
            }
            .toolbar {
                // Candado oculto si ya se desbloqueó (para poder re-bloquear). El desbloqueo
                // normal es con doble tirón hacia abajo (estilo Telegram), no con botón.
                ToolbarItem(placement: .topBarTrailing) {
                    if !allFavorites.isEmpty {
                        Button { settings.oneHandMode = true } label: { Image(systemName: "hand.point.up.left.fill") }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCategories = true } label: { Image(systemName: "folder.badge.gearshape") }
                }
            }
            .sheet(isPresented: $showCategories, onDismiss: reload) {
                NavigationStack { CategoriesManagerView() }
            }
            .fullScreenCover(isPresented: $settings.oneHandMode) {
                OneHandView(items: allFavorites.filter { !hiddenKeys.contains("\($0.sourceId)|\($0.id)") })
            }
            .task(id: lastCoverURL) { await loadDynamicColor() }
            .onAppear {
                reload()
                if AppSettings.shared.libraryCoverBackground, AppSettings.shared.backgroundGyro { bgMotion.start() }
            }
            .onDisappear { bgMotion.stop() }
        }
    }

    /// Color del velo: dinámico (de la portada) suavizado a pastel, o el acento por defecto.
    private var veilColor: Color { (dynamicColor ?? Color.mihonAccent).pastel(0.25) }

    /// ¿Mostrar la portada de fondo? (toggle de apariencia + que haya portada).
    private var showCoverBackground: Bool {
        AppSettings.shared.libraryCoverBackground && (lastCoverURL?.isEmpty == false)
    }

    /// Desplazamiento del fondo según el giroscopio (notorio pero suave). NO se mueve con el scroll.
    private var bgOffset: CGSize {
        guard AppSettings.shared.backgroundGyro else { return .zero }
        // Limitado para no revelar bordes (el margen es scaleEffect 1.22).
        let max: CGFloat = 60
        let x = min(max, Swift.max(-max, CGFloat(bgMotion.roll) * 55))
        let y = min(max, Swift.max(-max, CGFloat(bgMotion.pitch) * 55))
        return CGSize(width: x, height: y)
    }

    /// Fondo de Biblioteca: portada del último manga ABIERTO difuminada (reconocible) + velo de
    /// color DINÁMICO; o, si se desactiva, el degradado del tema. Se mueve con el giroscopio.
    private var libraryBackground: some View {
        ZStack {
            if showCoverBackground, let url = lastCoverURL, let u = URL(string: url) {
                CachedImage(url: u) { Color.clear }
                    .scaledToFill()
                    .blur(radius: 18)
                    .saturation(0.9)
                    .opacity(0.6)
                    .scaleEffect(1.22)                 // margen para el desplazamiento giroscópico
                    .offset(bgOffset)
                    .animation(.easeOut(duration: 0.3), value: bgOffset)
                LinearGradient(
                    colors: [veilColor.opacity(0.42), veilColor.opacity(0.12), AppTheme.endGray.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                )
            } else {
                AppTheme.gradient(AppSettings.shared.backgroundStyle, accent: AppSettings.shared.accentColor)
            }
            if !AppSettings.shared.patternEmoji.isEmpty { EmojiPattern(emoji: AppSettings.shared.patternEmoji) }
            if AppSettings.shared.particles { ParticleField() }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Vista de una estantería privada revelada por su palabra mágica.
    private func revealedShelf(_ shelf: Shelf) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Label("Estantería privada revelada", systemImage: "lock.open.fill")
                    .font(.caption.bold()).foregroundStyle(Color.mihonAccent)
                    .padding(.horizontal).padding(.top, 8)
                ShelfRow(shelf: shelf, onRename: { renameCategory($0, $1) }, onLongPress: { cardManga = $0 },
                             collapsed: settings.collapsedShelves.contains(Int(shelf.categoryId)),
                             onToggleCollapse: { toggleCollapse(shelf.categoryId) })
            }
            .padding(.vertical)
        }
        .scrollClipDisabled()
    }

    // Estanterías apiladas; cada una es un carrusel horizontal de portadas.
    private var shelvesList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(shelves, id: \.categoryId) { shelf in
                    ShelfRow(shelf: shelf, onRename: { renameCategory($0, $1) }, onLongPress: { cardManga = $0 },
                             collapsed: settings.collapsedShelves.contains(Int(shelf.categoryId)),
                             onToggleCollapse: { toggleCollapse(shelf.categoryId) })
                }
                // Estanterías privadas reveladas con Face ID.
                if unlockedPrivate {
                    ForEach(privateShelvesList, id: \.categoryId) { shelf in
                        VStack(alignment: .leading, spacing: 0) {
                            Label("Privada", systemImage: "lock.open.fill")
                                .font(.caption2.bold()).foregroundStyle(Color.mihonAccent)
                                .padding(.horizontal)
                            ShelfRow(shelf: shelf, onRename: { renameCategory($0, $1) }, onLongPress: { cardManga = $0 },
                             collapsed: settings.collapsedShelves.contains(Int(shelf.categoryId)),
                             onToggleCollapse: { toggleCollapse(shelf.categoryId) })
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        // Evita que el zoom al pulsar una portada se recorte contra los bordes del scroll.
        .scrollClipDisabled()
        // Telegram-style: dos tirones hacia abajo seguidos en el tope → desbloquea privadas (Face ID).
        .modifier(OverscrollDetector(action: handleOverscroll))
        .overlay(alignment: .top) {
            if hasPrivate, !unlockedPrivate, pullCount == 1 {
                Label("Tira otra vez para ver privadas", systemImage: "lock.fill")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    /// Detecta dos sobre-desplazamientos hacia abajo seguidos (re-armado al volver al tope).
    private func handleOverscroll(_ y: CGFloat) {
        guard hasPrivate, !unlockedPrivate else { return }
        if y < -85 {                        // tirón deliberado hacia abajo (overscroll relativo)
            if overscrollArmed {
                overscrollArmed = false
                pullCount += 1
                if pullCount >= 2 { pullCount = 0; unlockWithFaceID() }
            }
        } else if y > -20 {
            overscrollArmed = true
            if y > 50 { pullCount = 0 }       // bajó al contenido → reinicia la secuencia
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(filtered, id: \.compositeKey) { manga in
                    NavigationLink {
                        SourceMangaDetailView(sourceId: manga.sourceId, mangaId: manga.id,
                                              fallbackTitle: manga.title, fallbackThumb: manga.thumbnailUrl)
                    } label: {
                        LibraryCoverItem(manga: manga)
                    }
                    .buttonStyle(CardButtonStyle())
                    .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        cardManga = manga
                    })
                }
            }
            .padding(.horizontal)
        }
        .scrollClipDisabled()
    }

    /// Renombra una categoría creada (edición en línea desde el encabezado del estante).
    private func renameCategory(_ id: Int32, _ name: String) {
        try? MockData.bridgeInstance.renameCategory(id: id, name: name)
        reload()
    }

    /// Contrae/expande una estantería (categoría), persistido. Aplica a todas, incl. Tendencia y Sin categoría.
    private func toggleCollapse(_ categoryId: Int32) {
        let key = Int(categoryId)
        if settings.collapsedShelves.contains(key) { settings.collapsedShelves.remove(key) }
        else { settings.collapsedShelves.insert(key) }
    }

    /// Lectura local síncrona (SQLite). Se recarga al volver para reflejar cambios.
    private func reload() {
        allFavorites = (try? MockData.bridgeInstance.libraryManga()) ?? []
        // Estante "Tendencia" (lo más leído en las últimas 2 semanas) al inicio.
        var built: [Shelf] = []
        let cutoff = Int64((Date().timeIntervalSince1970 - 14 * 86_400) * 1000)
        let trending = (try? MockData.bridgeInstance.trendingManga(cutoff: cutoff, limit: 12)) ?? []
        if !trending.isEmpty {
            built.append(Shelf(categoryId: -2, name: "🔥 Tendencia", manga: trending))
        }
        built += (try? MockData.bridgeInstance.libraryShelves()) ?? []
        shelves = built
        hiddenKeys = Set((try? MockData.bridgeInstance.hiddenLibraryKeys()) ?? [])
        // Fondo dinámico = portada del último manga ABIERTO (no hace falta leer); si no, el último del historial.
        let viewed = AppSettings.shared.lastViewedCover
        lastCoverURL = viewed.isEmpty ? ((try? MockData.bridgeInstance.history())?.first?.thumbnailUrl ?? lastCoverURL) : viewed
        hasPrivate = ((try? MockData.bridgeInstance.categories()) ?? []).contains { !$0.magicWord.isEmpty }
        // Privacidad: al volver a la biblioteca, se vuelve a bloquear.
        unlockedPrivate = false
        privateShelvesList = []
        pullCount = 0
        overscrollArmed = true
    }

    /// Extrae el color dominante (promedio) de la portada del último leído para tintar el fondo.
    private func loadDynamicColor() async {
        guard let s = lastCoverURL, let u = URL(string: s),
              let img = await ImageCache.shared.image(for: u) else { return }
        if let color = img.averageColor() {
            withAnimation(.easeInOut(duration: 0.6)) { dynamicColor = color }
        }
    }

    private func unlockWithFaceID() {
        Task {
            if await Biometrics.authenticate(reason: "Revelar tus estanterías privadas") {
                let shelves = (try? MockData.bridgeInstance.privateShelves()) ?? []
                withAnimation { privateShelvesList = shelves; unlockedPrivate = true }
            }
        }
    }
}

/// Detecta el desplazamiento vertical del scroll (iOS 18+). En iOS 17 no hace nada.
private struct OverscrollDetector: ViewModifier {
    let action: (CGFloat) -> Void
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            // Overscroll RELATIVO al tope (0 en reposo, negativo al tirar hacia abajo). Así no
            // depende del offset inicial que mete el buscador/título grande.
            content.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in action(y) }
        } else {
            content
        }
    }
}

/// Una estantería: encabezado de categoría + carrusel horizontal de portadas.
/// En categorías CREADAS (id > 0) el nombre se edita: un toque muestra una pista y un segundo
/// toque abre la edición en línea.
private struct ShelfRow: View {
    let shelf: Shelf
    var onRename: ((Int32, String) -> Void)? = nil
    var onLongPress: ((BrowseManga) -> Void)? = nil
    var collapsed: Bool = false
    var onToggleCollapse: (() -> Void)? = nil

    @State private var editing = false
    @State private var editText = ""

    /// Solo las categorías creadas (no "Sin categoría" -1 ni "Tendencia" -2).
    private var editable: Bool { shelf.categoryId > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if editing {
                    TextField("Nombre", text: $editText)
                        .font(.title3.bold()).foregroundStyle(Color.mihonAccentText)
                        .textFieldStyle(.plain).submitLabel(.done)
                        .onSubmit { commit() }
                        .frame(maxWidth: 220)
                    Button("Guardar") { commit() }.font(.caption.bold())
                    Button { editing = false } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    // Tocar EN CUALQUIER PARTE del encabezado contrae/expande. (Renombrar = mantener pulsado.)
                    HStack(spacing: 8) {
                        Text(shelf.name).font(.title3.bold()).foregroundStyle(Color.mihonAccentText)
                        Text("\(shelf.manga.count)")
                            .font(.caption.bold()).foregroundStyle(.secondary)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.mihonAccentSoft.opacity(0.5), in: Capsule())
                        Spacer()
                        Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                            .font(.caption.bold()).foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onToggleCollapse?() }
                    .onLongPressGesture(minimumDuration: 0.4) { if editable { startEditing() } }
                }
            }
            .padding(.horizontal)
            .animation(.easeInOut(duration: 0.2), value: editing)

            if !collapsed {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(shelf.manga, id: \.compositeKey) { manga in
                        NavigationLink {
                            SourceMangaDetailView(sourceId: manga.sourceId, mangaId: manga.id,
                                                  fallbackTitle: manga.title, fallbackThumb: manga.thumbnailUrl)
                        } label: {
                            LibraryCoverItem(manga: manga).frame(width: 116)
                        }
                        .buttonStyle(CardButtonStyle())
                        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onLongPress?(manga)
                        })
                    }
                }
                .padding(.horizontal)
            }
            .scrollClipDisabled()
            }
        }
        .animation(.easeInOut(duration: 0.22), value: collapsed)
    }

    /// Renombrar (mantener pulsado el encabezado de una categoría creada): abre edición en línea.
    private func startEditing() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        editText = shelf.name
        withAnimation { editing = true }
    }

    private func commit() {
        let name = editText.trimmingCharacters(in: .whitespaces)
        editing = false
        if !name.isEmpty, name != shelf.name { onRename?(shelf.categoryId, name) }
    }
}

/// Portada de la biblioteca con carga real de imagen.
struct LibraryCoverItem: View {
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
                .collectibleBorder()

            Text(manga.title)
                .font(.caption).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    LibraryView()
}
