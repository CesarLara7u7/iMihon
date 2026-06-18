import SwiftUI
import Shared

/// Detalle de un manga de una fuente nativa: metadatos, botón de biblioteca y capítulos.
struct SourceMangaDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let sourceId: String
    let mangaId: String
    let fallbackTitle: String
    let fallbackThumb: String?

    @State private var detail: SourceMangaDetail?
    @State private var chapters: [SourceChapter] = []
    @State private var loadingChapters = true
    @State private var error: String?
    @State private var inLibrary = false
    @State private var togglingLibrary = false
    @State private var descExpanded = false
    @State private var reading: ReadingTarget?
    /// Progreso por capítulo (override local), refrescado al salir del lector.
    @State private var progressByChapter: [String: ChapterProgress] = [:]
    @State private var chapterFilter: ChapterFilter = .all
    @State private var coverZoomed = false
    @State private var showCategoryPicker = false
    @State private var selecting = false
    @State private var selected: Set<String> = []
    @State private var deleteTarget: DeleteTarget?
    @State private var descScale: CGFloat = 1
    @State private var isNsfwManga = false
    @State private var showInfo = false
    @Environment(\.openURL) private var openURL

    /// Capítulo cuya descarga se confirma eliminar.
    private struct DeleteTarget: Identifiable { let id: String; let name: String }

    enum ChapterFilter: String, CaseIterable {
        case all = "Todos", read = "Vistos", unread = "Por ver", new = "Nuevos"
    }

    private var weekAgoMs: Double { Date().timeIntervalSince1970 * 1000 - 7 * 24 * 60 * 60 * 1000 }
    private var hasRead: Bool { chapters.contains { progressByChapter[$0.id]?.read ?? $0.read } }
    private var hasNew: Bool { chapters.contains { Double($0.uploadDate) >= weekAgoMs } }

    /// Solo se muestran "Vistos"/"Nuevos" si hay capítulos en ese estado.
    private var availableFilters: [ChapterFilter] {
        ChapterFilter.allCases.filter {
            switch $0 {
            case .all, .unread: return true
            case .read: return hasRead
            case .new: return hasNew
            }
        }
    }

    /// Capítulos tras aplicar el filtro (vistos / por ver / nuevos<1 semana).
    private var filteredChapters: [SourceChapter] {
        let filter = availableFilters.contains(chapterFilter) ? chapterFilter : .all
        return chapters.filter { ch in
            let read = progressByChapter[ch.id]?.read ?? ch.read
            switch filter {
            case .all: return true
            case .read: return read
            case .unread: return !read
            case .new: return Double(ch.uploadDate) >= weekAgoMs
            }
        }
    }

    /// Capítulo a leer, para presentar el lector a pantalla completa.
    private struct ReadingTarget: Identifiable { let id: String; let name: String }

    /// Lista de capítulos en orden de lectura (ascendente) para el lector.
    private var readingOrder: [ReaderChapter] {
        chapters.reversed().map { ReaderChapter(id: $0.id, name: $0.name) }
    }

    var body: some View {
        List {
            header
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)

            Section {
                if loadingChapters {
                    HStack { ProgressView(); Text("Cargando capítulos…").foregroundStyle(.secondary) }
                } else if let error {
                    Text(error).foregroundStyle(.red).font(.footnote)
                } else {
                    ForEach(filteredChapters, id: \.id) { ch in
                        HStack(spacing: 10) {
                            if selecting {
                                Image(systemName: selected.contains(ch.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selected.contains(ch.id) ? Color.mihonAccent : .secondary)
                            }
                            Button {
                                if selecting { toggleSelect(ch) }
                                else { reading = ReadingTarget(id: ch.id, name: ch.name) }
                            } label: {
                                HStack {
                                    chapterRow(ch)
                                    Spacer()
                                    if !selecting {
                                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu { if !selecting { chapterMenuItems(ch) } }

                            // Menú de capítulo (descargar/marcar visto…) a la derecha.
                            if !selecting { downloadControl(ch) }
                        }
                        .listRowSeparatorTint(Color.mihonAccent.opacity(0.25))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            chapterDownloadAction(ch)
                        }
                    }
                }
            } header: {
                HStack {
                    Text(loadingChapters ? "Capítulos" : "\(filteredChapters.count) capítulos")
                    Spacer()
                    Menu {
                        ForEach(availableFilters, id: \.self) { f in
                            Button {
                                chapterFilter = f
                            } label: {
                                if chapterFilter == f { Label(f.rawValue, systemImage: "checkmark") }
                                else { Text(f.rawValue) }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text((availableFilters.contains(chapterFilter) ? chapterFilter : .all).rawValue)
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                        .font(.caption)
                        .foregroundStyle(Color.mihonAccentText)
                    }
                }
            }
        }
        .listStyle(.plain)
        .themedBackground()
        .overlay(alignment: .bottomTrailing) { continueFab }
        .overlay {
            if coverZoomed {
                CollectibleCardView(
                    imageURL: detail?.thumbnailUrl ?? fallbackThumb,
                    title: detail?.title ?? fallbackTitle,
                    author: detail?.author,
                    status: detail.map { statusLabel($0.status) },
                    genres: detail?.genres ?? [],
                    onClose: { withAnimation(.easeInOut(duration: 0.2)) { coverZoomed = false } }
                )
            }
        }
        .navigationTitle(detail?.title ?? fallbackTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(coverZoomed ? .hidden : .visible, for: .tabBar)
        .toolbar { detailToolbar }
        .task {
            // Fondo dinámico: el manga ABIERTO pasa a ser el fondo de Biblioteca (sin leer nada).
            if let thumb = fallbackThumb, !thumb.isEmpty { AppSettings.shared.lastViewedCover = thumb }
            await load()
        }
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPickerSheet(sourceId: sourceId, mangaId: mangaId)
                .presentationDetents([.medium, .large])
        }
        .alert("Marca +18", isPresented: $showInfo) {
            Button("OK") {}
            Button("No mostrar de nuevo") { AppSettings.shared.nsfwTipDismissed = true }
        } message: {
            Text("Los manga marcados +18 NO aparecen en Historial ni en Actualizaciones. "
                 + "Útil para contenido que prefieras mantener discreto.")
        }
        .alert("Eliminar descarga",
               isPresented: Binding(get: { deleteTarget != nil },
                                    set: { if !$0 { deleteTarget = nil } }),
               presenting: deleteTarget) { target in
            Button("Eliminar descarga", role: .destructive) {
                DownloadManager.shared.delete(sourceId, mangaId, target.id)
            }
            Button("Cancelar", role: .cancel) {}
        } message: { target in
            Text("Se borrará la descarga de “\(target.name)”.")
        }
        .fullScreenCover(item: $reading, onDismiss: { refreshProgress() }) { target in
            let order = readingOrder
            let start = order.firstIndex { $0.id == target.id } ?? 0
            SourceReaderView(
                sourceId: sourceId, mangaId: mangaId,
                mangaTitle: detail?.title ?? fallbackTitle,
                mangaThumb: detail?.thumbnailUrl ?? fallbackThumb,
                chapters: order, startIndex: start
            )
        }
    }

    /// Barra de herramientas del detalle: botón de regresar con zona táctil amplia (círculo
    /// de 44 pt) + acciones de descarga (o controles del modo selección).
    @ToolbarContentBuilder private var detailToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .accessibilityLabel("Volver")
        }
        if selecting {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Descargar (\(selected.count))") { downloadSelected() }
                    .disabled(selected.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Cancelar") { endSelecting() }
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) { optionsMenu }
        }
    }

    /// Menú de opciones del manga: marcar +18 (+ info), descargas, navegador y biblioteca.
    private var optionsMenu: some View {
        Menu {
            Button { toggleNsfw() } label: {
                Label(isNsfwManga ? "Quitar marca +18" : "Marcar como +18",
                      systemImage: isNsfwManga ? "eye" : "eye.slash")
            }
            Divider()
            Button { downloadAll() } label: { Label("Descargar todo", systemImage: "arrow.down.to.line") }
                .disabled(chapters.isEmpty)
            Button { downloadPending() } label: { Label("Descargar pendientes", systemImage: "arrow.down.circle.dotted") }
                .disabled(chapters.isEmpty)
            Button { startSelecting() } label: { Label("Seleccionar capítulos…", systemImage: "checklist") }
                .disabled(chapters.isEmpty)
            Divider()
            if let url = mangaWebURL() {
                Button { openURL(url) } label: { Label("Abrir en el navegador", systemImage: "safari") }
            }
            Divider()
            Button(role: .destructive) {
                DownloadManager.shared.deleteManga(sourceId, mangaId)
            } label: { Label("Eliminar descargas", systemImage: "trash.slash") }
            Button(role: .destructive) { purgeManga() } label: {
                Label("Eliminar", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle").frame(width: 40, height: 40).contentShape(Circle())
        }
    }

    /// Eliminar por COMPLETO: borra todo rastro del manga (biblioteca, historial, tendencias,
    /// progreso, prefs, +18, categorías, descargas) y sale del detalle.
    private func purgeManga() {
        DownloadManager.shared.deleteManga(sourceId, mangaId)   // archivos + filas de descarga
        try? MockData.bridgeInstance.purgeManga(
            sourceId: sourceId, mangaId: mangaId, now: Int64(Date().timeIntervalSince1970 * 1000))
        dismiss()
    }

    /// Botón flotante para continuar / empezar la lectura.
    @ViewBuilder private var continueFab: some View {
        if !chapters.isEmpty, !selecting {
            Button { continueReading() } label: {
                Label(progressByChapter.isEmpty ? "Empezar" : "Continuar", systemImage: "book.fill")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 6)
            }
            .glassProminentButton()
            .tint(.mihonAccent)
            .clipShape(Capsule())
            .shadow(radius: 6, y: 3)
            .padding()
        }
    }

    // MARK: - Cabecera

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                CachedImage(url: URL(string: detail?.thumbnailUrl ?? fallbackThumb ?? "")) {
                    CoverPlaceholder(title: detail?.title ?? fallbackTitle)
                }
                .scaledToFill()
                .frame(width: 110, height: 165)
                .coverCard(cornerRadius: 12)
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { coverZoomed = true } }

                VStack(alignment: .leading, spacing: 8) {
                    Text(detail?.title ?? fallbackTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.mihonAccentText)
                        .lineLimit(3)
                    if let author = detail?.author, !author.isEmpty {
                        TypewriterText(text: author)
                    }
                    if let detail {
                        HStack(spacing: 6) {
                            Circle().fill(Color.mihonAccent).frame(width: 7, height: 7)
                            Text(statusLabel(detail.status)).font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .liquidGlass(in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.mihonAccent.opacity(0.3), lineWidth: 0.8))
                    }
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Button {
                    Task { await toggleLibrary() }
                } label: {
                    Label(inLibrary ? "En biblioteca" : "Añadir a biblioteca",
                          systemImage: inLibrary ? "heart.fill" : "heart")
                        .frame(maxWidth: .infinity)
                }
                .glassProminentButton()
                .tint(inLibrary ? .gray : .mihonAccent)
                .disabled(togglingLibrary || detail == nil)

                if inLibrary {
                    Button { showCategoryPicker = true } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .glassButton()
                }
            }

            if let desc = detail?.description_, !desc.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(desc)
                        .font(.system(size: 15 * descScale, weight: .light))
                        .lineSpacing(3)
                        .lineLimit(descExpanded ? nil : 4)
                        .animation(.snappy, value: descScale)
                        .onTapGesture { withAnimation { descExpanded.toggle() } }

                    HStack(spacing: 16) {
                        Button { withAnimation(.snappy) { descScale = max(0.85, descScale - 0.1) } } label: {
                            Image(systemName: "textformat.size.smaller")
                        }
                        Button { withAnimation(.snappy) { descScale = min(1.7, descScale + 0.1) } } label: {
                            Image(systemName: "textformat.size.larger")
                        }
                        Spacer()
                        Button { withAnimation { descExpanded.toggle() } } label: {
                            Text(descExpanded ? "Ver menos" : "Ver más").font(.caption.bold())
                        }
                    }
                    .font(.body)
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.mihonAccentText)
                }
            }

            if let genres = detail?.genres, !genres.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(genres, id: \.self) { g in
                            Text(g).font(.caption.weight(.medium))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .liquidGlass(in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.mihonAccentSoft.opacity(0.7), lineWidth: 0.8))
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
            }
        }
        .padding()
    }

    private func chapterRow(_ ch: SourceChapter) -> some View {
        // El progreso local (override) tiene prioridad sobre lo que trajo la fuente.
        let p = progressByChapter[ch.id]
        let read = p?.read ?? ch.read
        let lastPage = p.map { Int($0.lastPage) } ?? Int(ch.lastPage)
        let inProgress = !read && lastPage > 0
        return HStack(spacing: 11) {
            // Indicador de estado: acento (sin leer), medio (en curso), tenue (leído).
            Circle()
                .fill(read ? Color.secondary.opacity(0.25) : Color.mihonAccent)
                .frame(width: 8, height: 8)
                .overlay { if inProgress { Circle().fill(.white).frame(width: 3, height: 3) } }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if ch.bookmark {
                        Image(systemName: "bookmark.fill").foregroundStyle(Color.mihonAccent).font(.caption)
                    }
                    Text(ch.name)
                        .font(.callout.weight(read ? .regular : .medium))
                        .foregroundStyle(read ? .secondary : .primary).lineLimit(1)
                }
                HStack(spacing: 8) {
                    if ch.uploadDate > 0 {
                        Text(Date(timeIntervalSince1970: TimeInterval(ch.uploadDate) / 1000), style: .date)
                    }
                    if let s = ch.scanlator, !s.isEmpty { Text("•"); Text(s).lineLimit(1) }
                    if read {
                        Text("•"); Label("Leído", systemImage: "checkmark").labelStyle(.titleOnly)
                    } else if lastPage > 0 {
                        Text("•"); Text("Página \(lastPage + 1)").foregroundStyle(Color.mihonAccent)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Carga / acciones

    private func load() async {
        isNsfwManga = (try? MockData.bridgeInstance.isMangaNsfw(sourceId: sourceId, mangaId: mangaId)) ?? false
        do {
            let d = try await MockData.bridgeInstance.mangaDetail(sourceId: sourceId, mangaId: mangaId)
            detail = d
            inLibrary = d.inLibrary
            if let thumb = d.thumbnailUrl, !thumb.isEmpty { AppSettings.shared.lastViewedCover = thumb }
        } catch {
            self.error = error.localizedDescription
        }
        do {
            chapters = try await MockData.bridgeInstance.sourceChapters(sourceId: sourceId, mangaId: mangaId)
            refreshProgress()
        } catch {
            self.error = "No se pudieron cargar los capítulos: \(error.localizedDescription)"
        }
        loadingChapters = false
    }

    /// Relee el progreso local (al cargar y al salir del lector) para actualizar la lista.
    private func refreshProgress() {
        progressByChapter = (try? MockData.bridgeInstance.chaptersProgress(sourceId: sourceId, mangaId: mangaId)) ?? [:]
    }

    /// Abre el capítulo en curso (último leído) o, si no hay, el primero por leer.
    private func continueReading() {
        guard !chapters.isEmpty else { return }
        let lastId = (try? MockData.bridgeInstance.lastReadChapter(sourceId: sourceId, mangaId: mangaId)) ?? nil
        let resolved = lastId.flatMap { id in chapters.first { $0.id == id } }
        if let target = resolved ?? chapters.last {   // chapters en desc → last = más antiguo = primero a leer
            reading = ReadingTarget(id: target.id, name: target.name)
        }
    }

    private func toggleLibrary() async {
        togglingLibrary = true
        let target = !inLibrary
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        do {
            try MockData.bridgeInstance.setFavorite(
                sourceId: sourceId,
                mangaId: mangaId,
                title: detail?.title ?? fallbackTitle,
                thumbnailUrl: detail?.thumbnailUrl ?? fallbackThumb,
                favorite: target,
                now: now
            )
            inLibrary = target
        } catch {
            self.error = error.localizedDescription
        }
        togglingLibrary = false
    }

    // MARK: - Descargas

    /// Control de descarga tocable a la derecha del capítulo: descarga/encola con un toque;
    /// si está en cola o descargando, lo cancela; si está descargado, lo indica.
    /// Control de capítulo: menú desplegable (descargar / marcar visto / no visto). El icono
    /// refleja el estado de descarga. El MISMO menú aparece al mantener presionado el capítulo.
    @ViewBuilder private func downloadControl(_ ch: SourceChapter) -> some View {
        Menu {
            chapterMenuItems(ch)
        } label: {
            chapterStatusIcon(ch)
        }
        .buttonStyle(.borderless)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func chapterStatusIcon(_ ch: SourceChapter) -> some View {
        switch DownloadManager.shared.item(sourceId, mangaId, ch.id)?.status {
        case nil:
            Image(systemName: "arrow.down.circle").font(.title3).foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "arrow.clockwise.circle").font(.title3).foregroundStyle(.red)
        case .queued:
            Image(systemName: "clock").font(.body).foregroundStyle(.secondary)
        case .downloading:
            Text("\(DownloadManager.shared.item(sourceId, mangaId, ch.id)?.downloadedPages ?? 0)/\(max(DownloadManager.shared.item(sourceId, mangaId, ch.id)?.totalPages ?? 1, 1))")
                .font(.caption2.monospacedDigit()).foregroundStyle(Color.mihonAccent)
        case .some(.done):
            Image(systemName: "arrow.down.circle.fill").font(.title3).foregroundStyle(Color.mihonAccent)
        }
    }

    /// Acciones del menú de un capítulo (compartidas por el control y el long-press).
    @ViewBuilder private func chapterMenuItems(_ ch: SourceChapter) -> some View {
        let status = DownloadManager.shared.item(sourceId, mangaId, ch.id)?.status
        let prog = progressByChapter[ch.id]
        let isRead = prog?.read ?? ch.read
        let hasProgress = isRead || (prog?.lastPage ?? 0) > 0
        switch status {
        case nil, .failed:
            Button { downloadChapter(ch) } label: { Label("Descargar", systemImage: "arrow.down.to.line") }
        case .queued, .downloading:
            Button(role: .destructive) { DownloadManager.shared.delete(sourceId, mangaId, ch.id) } label: {
                Label("Cancelar descarga", systemImage: "xmark.circle")
            }
        case .some(.done):
            Button(role: .destructive) { deleteTarget = DeleteTarget(id: ch.id, name: ch.name) } label: {
                Label("Eliminar descarga", systemImage: "trash")
            }
        }
        Divider()
        if !isRead {
            Button { markChapter(ch, read: true) } label: { Label("Marcar como visto", systemImage: "eye") }
        }
        if hasProgress {
            Button { markChapter(ch, read: false) } label: { Label("Marcar como no visto", systemImage: "eye.slash") }
        }
    }

    /// Marca el capítulo como visto (read=true) o no visto (borra el progreso) y refresca.
    private func markChapter(_ ch: SourceChapter, read: Bool) {
        try? MockData.bridgeInstance.setChapterRead(
            sourceId: sourceId, mangaId: mangaId, chapterId: ch.id,
            read: read, now: Int64(Date().timeIntervalSince1970 * 1000))
        refreshProgress()
    }

    private func toggleSelect(_ ch: SourceChapter) {
        if selected.contains(ch.id) { selected.remove(ch.id) } else { selected.insert(ch.id) }
    }

    private func startSelecting() { selected = []; selecting = true }
    private func endSelecting() { selecting = false; selected = [] }

    /// Descarga todos los capítulos.
    /// Marca/desmarca el manga como +18 (se excluye de Historial y Actualizaciones) y muestra el aviso.
    private func toggleNsfw() {
        let target = !isNsfwManga
        try? MockData.bridgeInstance.setMangaNsfw(sourceId: sourceId, mangaId: mangaId, nsfw: target)
        withAnimation(.snappy) { isNsfwManga = target }
        if target, !AppSettings.shared.nsfwTipDismissed { showInfo = true }
    }

    /// URL del manga en la web de la fuente (para "Abrir en el navegador").
    private func mangaWebURL() -> URL? {
        let s: String
        if sourceId.hasPrefix("mangadex-") { s = "https://mangadex.org/title/\(mangaId)" }
        else if sourceId.hasPrefix("mangaplus-") { s = "https://mangaplus.shueisha.co.jp/titles/\(mangaId)" }
        else if sourceId.hasPrefix("comick-") { s = "https://comick.live/comic/\(mangaId)" }
        else if sourceId.hasPrefix("mangafire-") { s = "https://mangafire.to/\(mangaId)" }
        else { return nil }
        return URL(string: s)
    }

    private func downloadAll() { enqueueDownloads(chapters) }

    /// Descarga solo los capítulos pendientes (no leídos).
    private func downloadPending() {
        enqueueDownloads(chapters.filter { !(progressByChapter[$0.id]?.read ?? $0.read) })
    }

    /// Descarga los capítulos marcados en el modo selección.
    private func downloadSelected() {
        enqueueDownloads(chapters.filter { selected.contains($0.id) })
        endSelecting()
    }

    private func enqueueDownloads(_ chs: [SourceChapter]) {
        DownloadManager.shared.downloadSeries(
            sourceId: sourceId, mangaId: mangaId,
            mangaTitle: detail?.title ?? fallbackTitle, thumbnailUrl: detail?.thumbnailUrl ?? fallbackThumb,
            chapters: chs.map { (id: $0.id, name: $0.name) }
        )
    }

    @ViewBuilder private func chapterDownloadAction(_ ch: SourceChapter) -> some View {
        let status = DownloadManager.shared.item(sourceId, mangaId, ch.id)?.status
        if status == nil || status == .failed {
            Button { downloadChapter(ch) } label: { Label("Descargar", systemImage: "arrow.down") }
                .tint(.mihonAccent)
        } else {
            Button(role: .destructive) {
                DownloadManager.shared.delete(sourceId, mangaId, ch.id)
            } label: { Label("Eliminar", systemImage: "trash") }
        }
    }

    private func downloadChapter(_ ch: SourceChapter) {
        DownloadManager.shared.download(
            sourceId: sourceId, mangaId: mangaId,
            mangaTitle: detail?.title ?? fallbackTitle, thumbnailUrl: detail?.thumbnailUrl ?? fallbackThumb,
            chapterId: ch.id, chapterName: ch.name
        )
    }

    private func statusLabel(_ s: String) -> String {
        switch s {
        case "ONGOING": return "En emisión"
        case "COMPLETED": return "Completado"
        case "LICENSED": return "Licenciado"
        case "PUBLISHING_FINISHED": return "Publicación finalizada"
        case "CANCELLED": return "Cancelado"
        case "ON_HIATUS": return "En pausa"
        default: return "Desconocido"
        }
    }
}
