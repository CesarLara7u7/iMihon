import SwiftUI
import UIKit
import Shared

/// Capítulo para el lector (orden de lectura ascendente).
struct ReaderChapter: Identifiable, Hashable {
    let id: String
    let name: String
}

/// Preferencias de lectura (espejo de `ReadingPrefs` del módulo compartido).
struct ReaderPrefs: Equatable {
    var colorFilter: Int = 0   // 0 ninguno, 1 B/N, 2 sepia, 3 sepia suave
    var intensity: Double = 1.0
    var direction: Int = 1     // 0 izq→der, 1 der→izq (RTL, por defecto)
    var mode: Int = 0          // 0 paginado, 1 webtoon
    var doublePage: Int = 0    // 0 no, 1 sí (páginas anchas como 2 mitades)
}

/// Lector v2: modos paginado/webtoon, dirección RTL, filtros de color, zoom persistente,
/// HUD inmersivo (solo al tocar), página de fin y auto-avance al siguiente capítulo.
struct SourceReaderView: View {
    @Environment(\.dismiss) private var dismiss

    let sourceId: String
    let mangaId: String
    let mangaTitle: String
    let mangaThumb: String?
    let chapters: [ReaderChapter]
    let startIndex: Int

    @State private var chapterIndex: Int
    @State private var pages: [String] = []
    @State private var phase: Phase = .loading
    @State private var current = 0
    @State private var showBar = false      // HUD oculto por defecto: solo lectura
    @State private var chapterRead = false
    @State private var prefs = ReaderPrefs()
    @State private var showOptions = false
    // Webtoon: página visible actual (para el scrubber lateral; bidireccional, no como `current`).
    @State private var webtoonPage = 0
    // Webtoon "estirar para continuar" (sobre-desplazamiento al final).
    @State private var webtoonPull: CGFloat = 0
    @State private var webtoonArmed = true
    @State private var webtoonHapticStep = 0
    // Estirar al INICIO para regresar al capítulo anterior (solo vibración, sin página auxiliar).
    @State private var topArmed = true
    @State private var topHapticStep = -1
    @State private var pagedBackProgress: CGFloat = 0
    @State private var pagedBackStep = 0
    /// Progreso visible del gesto "capítulo anterior" (0…1), para el indicador en pantalla.
    @State private var backStretch: CGFloat = 0
    private let advanceThreshold: CGFloat = 130
    private let hapticGen = UIImpactFeedbackGenerator(style: .medium)
    @State private var sessionStart = Date()

    enum Phase: Equatable { case loading, ready, failed(String) }

    init(sourceId: String, mangaId: String, mangaTitle: String, mangaThumb: String?,
         chapters: [ReaderChapter], startIndex: Int) {
        self.sourceId = sourceId
        self.mangaId = mangaId
        self.mangaTitle = mangaTitle
        self.mangaThumb = mangaThumb
        self.chapters = chapters
        self.startIndex = startIndex
        _chapterIndex = State(initialValue: startIndex)
    }

    private var chapter: ReaderChapter { chapters[chapterIndex] }
    private var hasNext: Bool { chapterIndex + 1 < chapters.count }
    private var hasPrev: Bool { chapterIndex > 0 }
    private var isEndPage: Bool { current == pages.count }
    private var isWebtoon: Bool { prefs.mode == 1 }
    private var incognito: Bool { AppSettings.shared.incognito }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch phase {
            case .loading:
                ProgressView("Cargando páginas…").tint(.white).foregroundStyle(.white)
            case .failed(let msg):
                failedView(msg)
            case .ready:
                content
                    .modifier(ReaderColorFilter(filter: prefs.colorFilter, intensity: prefs.intensity))
            }

            if showBar {
                topBar
                if phase == .ready, !isWebtoon, !isEndPage, pages.count > 1 { bottomBar }
            }

            // Indicador "Capítulo anterior" mientras se estira al inicio (paginado o webtoon).
            if hasPrev, backStretch > 0.02 {
                VStack(spacing: 10) {
                    AdvanceIndicator(progress: backStretch, arrow: "chevron.backward")
                    Text("Capítulo anterior").font(.subheadline.bold()).foregroundStyle(.white)
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 70)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: backStretch > 0.02)
        .statusBarHidden(!showBar)
        .task { sessionStart = Date(); await loadPrefsAndPages() }
        .onDisappear { recordReadingTime() }
        .onChange(of: current) { _, page in
            // Llegar a la página disparadora (tras la de fin) carga el siguiente capítulo.
            if !isWebtoon, hasNext, page == pages.count + 1 {
                Task { await advance() }
            } else {
                saveProgress(page: page)
                prefetchAhead(from: page)
            }
        }
        .sheet(isPresented: $showOptions) {
            ReaderOptionsSheet(prefs: $prefs).presentationDetents([.medium, .large])
        }
        // Guarda las prefs POR MANGA solo tras cerrar el panel (interacción explícita);
        // así cambiar el valor global sigue afectando a los manga sin personalizar.
        .onChange(of: showOptions) { _, shown in if !shown { savePrefs() } }
    }

    @ViewBuilder private var content: some View {
        if isWebtoon { webtoonReader } else { pagedReader }
    }

    // MARK: - Paginado

    private var pagedReader: some View {
        TabView(selection: $current) {
            ForEach(Array(pages.enumerated()), id: \.offset) { idx, url in
                ReaderPageView(url: url, rtl: prefs.direction == 1,
                               doublePage: prefs.doublePage == 1, onSingleTap: { toggleBar() })
                    .tag(idx)
            }
            EndPage(hasNext: hasNext,
                    nextTitle: hasNext ? chapters[chapterIndex + 1].name : nil,
                    mode: 0, direction: prefs.direction, webtoonProgress: 0,
                    onClose: { dismiss() })
                .tag(pages.count)
            // Página "disparadora": deslizar hasta aquí (una página más, nativo) carga el siguiente.
            if hasNext {
                advanceTriggerPage.tag(pages.count + 1)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .environment(\.layoutDirection, prefs.direction == 1 ? .rightToLeft : .leftToRight)
        .ignoresSafeArea()
        // En la PRIMERA página, estirar hacia atrás da háptica gradual y, al soltar, carga el
        // capítulo anterior (sin página auxiliar; igual sensación que el final).
        .overlay { if hasPrev { PanHapticObserver { tx in handlePagedBackPan(tx) } } }
    }

    /// Háptica al estirar hacia atrás en la primera página → al soltar pasado el umbral, capítulo anterior.
    private func handlePagedBackPan(_ translationX: CGFloat) {
        if translationX == 0 {                          // gesto terminó
            if pagedBackProgress >= 1 { Task { await goPrevious() } }
            pagedBackProgress = 0; pagedBackStep = 0; backStretch = 0
            return
        }
        guard hasPrev, current == 0 else { pagedBackProgress = 0; backStretch = 0; return }
        let backward = prefs.direction == 1 ? -translationX : translationX
        let progress = min(1, max(0, backward / advanceThreshold))
        pagedBackProgress = progress
        backStretch = progress
        let step = Int(progress * 20)
        if step != pagedBackStep {
            pagedBackStep = step
            if progress > 0 { hapticGen.impactOccurred(intensity: CGFloat(0.2 + 0.8 * progress)) }
        }
    }

    /// Página tras la de fin: al deslizar hasta ella (paginado nativo) carga el siguiente capítulo.
    private var advanceTriggerPage: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large).tint(.white)
            Text("Cargando siguiente capítulo… \(Kaomoji.pick(Kaomoji.loading, seed: 4))")
                .font(.callout).foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    // MARK: - Webtoon (scroll vertical continuo)

    private var webtoonReader: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { idx, url in
                        CachedImage(url: URL(string: url)) {
                            ProgressView().tint(.white).frame(height: 300)
                        }
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .id(idx)
                        .onAppear { webtoonPage = idx; if idx > current { current = idx } }
                    }
                    EndPage(hasNext: hasNext,
                            nextTitle: hasNext ? chapters[chapterIndex + 1].name : nil,
                            mode: 1, direction: prefs.direction,
                            webtoonProgress: min(1, webtoonPull / advanceThreshold),
                            onClose: { dismiss() })
                        .frame(height: 360)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea()
            .modifier(BottomOverscrollDetector(action: handleWebtoonOverscroll))
            .modifier(TopOverscrollDetector(action: handleTopOverscroll))
            .onTapGesture { toggleBar() }
            // Scrubber lateral delgado: muestra la página y permite saltar entre páginas.
            .overlay(alignment: .trailing) {
                if pages.count > 1 {
                    WebtoonScrubber(current: webtoonPage, total: pages.count) { page in
                        webtoonPage = page
                        if page > current { current = page }
                        proxy.scrollTo(page, anchor: .top)
                    }
                }
            }
        }
    }

    /// Webtoon: sobre-desplazar por ENCIMA del inicio da háptica gradual y, al pasar el umbral,
    /// carga el capítulo anterior (solo vibración, sin página auxiliar).
    private func handleTopOverscroll(_ over: CGFloat) {
        guard hasPrev else { return }
        if over <= 4 { topArmed = true; topHapticStep = -1; backStretch = 0; return }
        let progress = min(1, over / advanceThreshold)
        backStretch = progress
        let step = Int(progress * 20)
        if step != topHapticStep {
            topHapticStep = step
            hapticGen.impactOccurred(intensity: CGFloat(0.2 + 0.8 * progress))
        }
        if topArmed, over >= advanceThreshold {
            topArmed = false
            backStretch = 0
            Task { await goPrevious() }
        }
    }

    /// Webtoon "estirar para continuar": al sobre-desplazar por debajo del final se llena el
    /// progreso (con háptica) y, al pasar el umbral, carga el siguiente capítulo. Si regresas, se
    /// desactiva y reinicia.
    private func handleWebtoonOverscroll(_ over: CGFloat) {
        guard hasNext else { return }
        if over <= 4 {
            webtoonArmed = true; webtoonPull = 0; webtoonHapticStep = -1
            return
        }
        webtoonPull = over
        // Háptica GRADUAL atada al dedo: 20 escalones; la intensidad sube con el arrastre
        // (suave al empezar → fuerte al completar). Se SIENTE el avance al deslizar.
        let progress = min(1, over / advanceThreshold)
        let step = Int(progress * 20)
        if step != webtoonHapticStep {
            webtoonHapticStep = step
            hapticGen.impactOccurred(intensity: CGFloat(0.2 + 0.8 * progress))
        }
        if webtoonArmed, over >= advanceThreshold {
            webtoonArmed = false
            Task { await advance() }
        }
    }


    private func failedView(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle)
            Text("No se pudieron cargar las páginas").font(.headline)
            Text(msg).font(.footnote).multilineTextAlignment(.center).padding(.horizontal)
            Button("Reintentar") { Task { await load() } }.buttonStyle(.borderedProminent)
            Button("Cerrar") { dismiss() }.tint(.gray)
        }
        .foregroundStyle(.white).padding()
    }

    // MARK: - HUD

    private var topBar: some View {
        VStack {
            HStack(spacing: 8) {
                barButton("chevron.left") { dismiss() }
                Text(chapter.name).lineLimit(1).font(.subheadline.weight(.medium))
                if incognito { Image(systemName: "eyeglasses").font(.subheadline).foregroundStyle(.white.opacity(0.8)) }
                Spacer()
                if !isWebtoon, current < pages.count {
                    Text("\(current + 1) / \(pages.count)").font(.subheadline.monospacedDigit())
                }
                barButton("textformat.size") { showOptions = true }
            }
            .padding(.horizontal, 8).padding(.top, 6)
            .foregroundStyle(.white)
            .liquidGlass(in: Rectangle())
            .environment(\.colorScheme, .dark)
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Botón del HUD con zona táctil amplia (44 pt) y fondo circular para que sea fácil de tocar.
    private func barButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(.white.opacity(0.14)))
                .contentShape(Circle())
        }
    }

    private var bottomBar: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Text("\(current + 1)").font(.caption.monospacedDigit())
                Slider(
                    value: Binding(
                        get: { Double(min(current, pages.count - 1)) },
                        set: { newValue in
                            withAnimation(.easeInOut(duration: 0.15)) { current = Int(newValue.rounded()) }
                        }
                    ),
                    in: 0...Double(max(pages.count - 1, 1)), step: 1
                )
                .environment(\.layoutDirection, prefs.direction == 1 ? .rightToLeft : .leftToRight)
                Text("\(pages.count)").font(.caption.monospacedDigit())
            }
            .padding(.horizontal).padding(.vertical, 10).padding(.bottom, 8)
            .foregroundStyle(.white)
            .liquidGlass(in: Rectangle())
            .environment(\.colorScheme, .dark)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func toggleBar() { withAnimation(.easeInOut(duration: 0.2)) { showBar.toggle() } }

    // MARK: - Carga / navegación

    private func loadPrefsAndPages() async {
        if let p = try? MockData.bridgeInstance.readingPrefs(sourceId: sourceId, mangaId: mangaId) {
            prefs = ReaderPrefs(colorFilter: Int(p.colorFilter), intensity: p.intensity,
                                direction: Int(p.direction), mode: Int(p.mode),
                                doublePage: Int(p.doublePage))
        } else {
            // Sin prefs propias: parte de los valores globales por defecto.
            let s = AppSettings.shared
            prefs = ReaderPrefs(colorFilter: s.defaultColorFilter, intensity: s.defaultIntensity,
                                direction: s.defaultDirection, mode: s.defaultMode,
                                doublePage: s.doublePageDefault ? 1 : 0)
        }
        await load()
    }

    private func load() async {
        phase = .loading
        chapterRead = false
        current = 0
        do {
            // Offline primero: si el capítulo está descargado, lee de disco.
            if let local = DownloadManager.shared.localPages(sourceId, mangaId, chapter.id) {
                pages = local
            } else {
                pages = try await MockData.bridgeInstance.chapterPages(sourceId: sourceId, chapterId: chapter.id)
            }
            if pages.isEmpty { phase = .failed("El capítulo no devolvió páginas."); return }
            if !incognito, let p = try? MockData.bridgeInstance.chapterProgress(sourceId: sourceId, mangaId: mangaId, chapterId: chapter.id) {
                current = min(Int(p.lastPage), pages.count - 1)
                chapterRead = p.read
            }
            if !incognito {
                try? MockData.bridgeInstance.recordHistory(
                    sourceId: sourceId, mangaId: mangaId, mangaTitle: mangaTitle, thumbnailUrl: mangaThumb,
                    chapterId: chapter.id, chapterName: chapter.name,
                    now: Int64(Date().timeIntervalSince1970 * 1000)
                )
            }
            phase = .ready
            prefetchAhead(from: current)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Descarga perezosa: precarga las 3 páginas siguientes para evitar el salto al pasar.
    private func prefetchAhead(from page: Int) {
        guard !pages.isEmpty else { return }
        let next = ((page + 1)...(page + 3)).compactMap { i in
            i < pages.count ? URL(string: pages[i]) : nil
        }
        ImageCache.shared.prefetch(next)
    }

    /// Acumula el tiempo de esta sesión de lectura para el estante "Tendencia" (no en incógnito).
    private func recordReadingTime() {
        guard !incognito else { return }
        let secs = Int(Date().timeIntervalSince(sessionStart))
        guard secs > 2 else { return }
        try? MockData.bridgeInstance.addReadingTime(
            sourceId: sourceId, mangaId: mangaId, mangaTitle: mangaTitle, thumbnailUrl: mangaThumb,
            seconds: Int32(secs), now: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }

    private func advance() async {
        markRead()
        guard hasNext else { dismiss(); return }
        chapterIndex += 1
        await load()
    }

    /// Va al capítulo ANTERIOR (al estirar al inicio). No marca como leído el actual.
    private func goPrevious() async {
        guard hasPrev else { return }
        chapterIndex -= 1
        await load()
    }

    private func saveProgress(page: Int) {
        guard phase == .ready, !pages.isEmpty, !incognito else { return }
        if page >= pages.count - 1 { chapterRead = true }
        let clamped = min(page, pages.count - 1)
        try? MockData.bridgeInstance.saveChapterProgress(
            sourceId: sourceId, mangaId: mangaId, chapterId: chapter.id,
            lastPage: Int32(clamped), read: chapterRead, now: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }

    private func markRead() {
        chapterRead = true
        guard !pages.isEmpty, !incognito else { return }
        try? MockData.bridgeInstance.saveChapterProgress(
            sourceId: sourceId, mangaId: mangaId, chapterId: chapter.id,
            lastPage: Int32(pages.count - 1), read: true, now: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }

    private func savePrefs() {
        try? MockData.bridgeInstance.saveReadingPrefs(
            sourceId: sourceId, mangaId: mangaId,
            colorFilter: Int32(prefs.colorFilter), intensity: prefs.intensity,
            direction: Int32(prefs.direction), mode: Int32(prefs.mode),
            doublePage: Int32(prefs.doublePage)
        )
    }
}

// MARK: - Opciones de lectura

private struct ReaderOptionsSheet: View {
    @Binding var prefs: ReaderPrefs
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                ReadingControls(
                    mode: $prefs.mode,
                    direction: $prefs.direction,
                    colorFilter: $prefs.colorFilter,
                    intensity: $prefs.intensity,
                    doublePage: Binding(get: { prefs.doublePage == 1 },
                                        set: { prefs.doublePage = $0 ? 1 : 0 })
                )
            }
            .navigationTitle("Opciones de lectura")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
        }
    }
}

/// Filtro de color aplicado a las páginas (B/N, sepia, sepia suave) con intensidad.
private struct ReaderColorFilter: ViewModifier {
    let filter: Int
    let intensity: Double

    func body(content: Content) -> some View {
        switch filter {
        case 1: content.grayscale(intensity)
        case 2: content.grayscale(1).colorMultiply(sepia(r: 1.0, g: 0.72, b: 0.40))
        case 3: content.grayscale(1).colorMultiply(sepia(r: 1.0, g: 0.87, b: 0.70))
        default: content
        }
    }

    /// Interpola blanco → tono sepia según la intensidad.
    private func sepia(r: Double, g: Double, b: Double) -> Color {
        Color(red: 1 - (1 - r) * intensity, green: 1 - (1 - g) * intensity, blue: 1 - (1 - b) * intensity)
    }
}

/// Página de fin de capítulo: mensaje de descanso/continuar + transición "estirar" (estilo
/// YouTube) para cargar el siguiente capítulo.
/// - Paginado: se estira con un arrastre EN DIRECCIÓN DE LECTURA (RTL/LTR), en TODA la pantalla.
/// - Webtoon: el progreso lo manda el sobre-desplazamiento del scroll (`webtoonProgress`).
private struct EndPage: View {
    let hasNext: Bool
    let nextTitle: String?
    let mode: Int                 // 0 paginado, 1 webtoon
    let direction: Int            // 0 LTR, 1 RTL (para la dirección del arrastre en paginado)
    let webtoonProgress: CGFloat  // solo webtoon (lo manda el sobre-desplazamiento del scroll)
    let onClose: () -> Void

    @State private var hapticStep = 0
    private let hapticGen = UIImpactFeedbackGenerator(style: .medium)

    private static let restMessages = [
        "Buen momento para descansar la vista 👀",
        "Un capítulo más… o un respiro. Tú decides ✨",
        "Estírate un poco antes de seguir 🧘",
        "Hidrátate y vuelve cuando quieras 💧",
        "Tu historia te espera, sin prisa 🌙",
    ]
    @State private var message = Self.restMessages.randomElement() ?? ""
    @State private var hintPulse = false
    private let threshold: CGFloat = 130

    private var progress: CGFloat { min(1, max(0, webtoonProgress)) }

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 50)).foregroundStyle(Color.mihonAccent)
            Text("Capítulo terminado").font(.title3.bold()).foregroundStyle(.white)
            if AppSettings.shared.restMessages {
                Text(message)
                    .font(.subheadline).foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center).padding(.horizontal, 36)
            }

            if hasNext {
                if let nextTitle {
                    Text("Siguiente: \(nextTitle)")
                        .font(.caption).foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center).lineLimit(2).padding(.horizontal)
                }
                if mode == 1 {
                    // Webtoon: estirar (sobre-desplazamiento) para continuar.
                    AdvanceIndicator(progress: progress, arrow: "chevron.up")
                        .offset(y: -webtoonProgress * threshold * 0.3)
                        .padding(.top, 6)
                    Text(progress >= 1 ? "¡Suelta para continuar!" : "Sigue tirando para continuar")
                        .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.85))
                } else {
                    // Paginado: avanzar es deslizar a la siguiente página (`chevron.forward` se
                    // auto-orienta a la dirección de lectura del lector).
                    Image(systemName: "chevron.compact.forward")
                        .font(.system(size: 40, weight: .semibold)).foregroundStyle(Color.mihonAccent)
                        .offset(x: hintPulse ? 7 : -3)
                        .padding(.top, 6)
                    Text("Desliza para el siguiente capítulo")
                        .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.85))
                }
            } else {
                Text("No hay más capítulos").font(.subheadline).foregroundStyle(.white.opacity(0.7))
                Button("Cerrar", action: onClose).glassButton().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        // Paginado: OBSERVA el arrastre del dedo a nivel UIKit (reconocimiento simultáneo, NO
        // bloquea la paginación nativa) y da háptica gradual atada al gesto, igual que webtoon.
        .overlay {
            if mode == 0, hasNext {
                PanHapticObserver { tx in handlePagedPan(tx) }
            }
        }
        .onAppear {
            if mode == 0, hasNext {
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { hintPulse = true }
            }
        }
    }

    private func handlePagedPan(_ translationX: CGFloat) {
        if translationX == 0 { hapticStep = 0; return }   // gesto terminó
        let forward = direction == 1 ? translationX : -translationX
        let progress = min(1, max(0, forward / threshold))
        let step = Int(progress * 20)
        if step != hapticStep {
            hapticStep = step
            if progress > 0 { hapticGen.impactOccurred(intensity: CGFloat(0.2 + 0.8 * progress)) }
        }
    }
}

/// Observa el desplazamiento horizontal del dedo SIN bloquear otros gestos (paginación del
/// TabView). Reporta `translation.x` (0 al terminar). Vía UIKit por reconocimiento simultáneo.
private struct PanHapticObserver: UIViewRepresentable {
    let onTranslation: (CGFloat) -> Void

    func makeUIView(context: Context) -> PassthroughView {
        let view = PassthroughView()
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handle(_:)))
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = false   // NO roba toques: observa sin bloquear
        view.pan = pan
        return view
    }

    func updateUIView(_ uiView: PassthroughView, context: Context) { context.coordinator.onTranslation = onTranslation }

    func makeCoordinator() -> Coordinator { Coordinator(onTranslation: onTranslation) }

    /// Vista transparente que NUNCA intercepta toques (hitTest nil); el recognizer va en la ventana
    /// para observar el arrastre sin bloquear la paginación del TabView ni los toques.
    final class PassthroughView: UIView {
        var pan: UIPanGestureRecognizer?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let w = window, let pan, pan.view == nil { w.addGestureRecognizer(pan) }
            else if window == nil, let pan { pan.view?.removeGestureRecognizer(pan) }
        }
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTranslation: (CGFloat) -> Void
        init(onTranslation: @escaping (CGFloat) -> Void) { self.onTranslation = onTranslation }

        @objc func handle(_ g: UIPanGestureRecognizer) {
            switch g.state {
            case .changed: onTranslation(g.translation(in: g.view).x)
            case .ended, .cancelled, .failed: onTranslation(0)
            default: break
            }
        }

        // Reconoce a la vez que el resto (no bloquea).
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

/// Scrubber lateral delgado para webtoon: muestra la página actual y, al arrastrarlo, salta entre
/// páginas. Vive en el borde derecho; no estorba al scroll vertical (zona táctil estrecha).
private struct WebtoonScrubber: View {
    let current: Int          // página visible (0-based)
    let total: Int
    let onScrub: (Int) -> Void

    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let frac = total > 1 ? CGFloat(current) / CGFloat(total - 1) : 0
            let thumbY = max(0, min(h, frac * h))
            ZStack(alignment: .topTrailing) {
                Capsule()
                    .fill(.white.opacity(0.2))
                    .frame(width: dragging ? 6 : 5)
                    .frame(maxHeight: .infinity)
                    .padding(.trailing, 10)

                HStack(spacing: 8) {
                    Text("\(current + 1)/\(total)")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .opacity(dragging ? 1 : 0)
                    Capsule()
                        .fill(Color.mihonAccent)
                        .frame(width: dragging ? 16 : 11, height: dragging ? 80 : 54)
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                }
                .offset(y: thumbY - (dragging ? 40 : 27))
                .animation(.easeOut(duration: 0.15), value: dragging)
            }
            .frame(width: 60, alignment: .trailing)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        dragging = true
                        let f = max(0, min(1, v.location.y / h))
                        let page = Int((f * CGFloat(total - 1)).rounded())
                        if page != current { onScrub(page) }
                    }
                    .onEnded { _ in dragging = false }
            )
        }
        .frame(width: 60)
        .padding(.vertical, 50)
    }
}

/// Anillo de progreso de "estirar para continuar" con flecha en la dirección de avance.
private struct AdvanceIndicator: View {
    let progress: CGFloat
    let arrow: String

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: 4)
            Circle().trim(from: 0, to: progress)
                .stroke(Color.mihonAccent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: progress >= 1 ? "checkmark" : arrow)
                .font(.title3.weight(.bold)).foregroundStyle(.white)
                .scaleEffect(1 + progress * 0.3)
        }
        .frame(width: 60, height: 60)
        .scaleEffect(1 + progress * 0.18)
    }
}

/// Detecta el sobre-desplazamiento por DEBAJO del final del scroll (iOS 18+). Para "estirar para
/// continuar" en webtoon. Valor > 0 = tiraste hacia arriba más allá del final.
private struct BottomOverscrollDetector: ViewModifier {
    let action: (CGFloat) -> Void
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) {
                $0.contentOffset.y + $0.containerSize.height - $0.contentSize.height - $0.contentInsets.bottom
            } action: { _, v in action(v) }
        } else {
            content
        }
    }
}

/// Detecta el sobre-desplazamiento por ENCIMA del inicio del scroll (iOS 18+). Para "estirar para
/// regresar" en webtoon. Valor > 0 = tiraste hacia abajo más allá del inicio.
private struct TopOverscrollDetector: ViewModifier {
    let action: (CGFloat) -> Void
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) {
                -($0.contentOffset.y + $0.contentInsets.top)
            } action: { _, v in action(v) }
        } else {
            content
        }
    }
}

/// Página del lector paginado. Carga la imagen desde la caché (se beneficia del prefetch),
/// detecta las páginas dobles (spreads) por su resolución y, en ese caso, las acerca para
/// leerlas como 2 mitades. Las normales mantienen el zoom persistente.
private struct ReaderPageView: View {
    let url: String
    let rtl: Bool
    let doublePage: Bool
    let onSingleTap: () -> Void

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
                ZoomableScrollView(onSingleTap: onSingleTap,
                                   wideAspect: (doublePage && aspect > 1.2) ? aspect : nil, rtl: rtl) {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ProgressView().tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { onSingleTap() }
            }
        }
        .task(id: url) {
            if let u = URL(string: url) { image = await ImageCache.shared.image(for: u) }
        }
    }
}

/// Contenedor de zoom basado en UIScrollView: el zoom PERSISTE (no rebota); doble toque restaura.
/// Deja pasar el deslizamiento horizontal al paginador cuando no hay zoom.
struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    private let content: Content
    private let onSingleTap: () -> Void
    private let wideAspect: CGFloat?
    private let rtl: Bool

    init(onSingleTap: @escaping () -> Void, wideAspect: CGFloat? = nil, rtl: Bool = false,
         @ViewBuilder content: () -> Content) {
        self.onSingleTap = onSingleTap
        self.wideAspect = wideAspect
        self.rtl = rtl
        self.content = content()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 5
        scrollView.minimumZoomScale = 1
        scrollView.bouncesZoom = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear

        let hosted = context.coordinator.hostingController.view!
        hosted.translatesAutoresizingMaskIntoConstraints = false
        hosted.backgroundColor = .clear
        scrollView.addSubview(hosted)
        NSLayoutConstraint.activate([
            hosted.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hosted.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hosted.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hosted.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hosted.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            hosted.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.hostingController.rootView = content
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.applyWideIfNeeded(uiView, aspect: wideAspect, rtl: rtl)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(hostingController: UIHostingController(rootView: content), onSingleTap: onSingleTap)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let hostingController: UIHostingController<Content>
        var onSingleTap: () -> Void
        private var appliedWide = false

        init(hostingController: UIHostingController<Content>, onSingleTap: @escaping () -> Void) {
            self.hostingController = hostingController
            self.onSingleTap = onSingleTap
            super.init()
            hostingController.view.backgroundColor = .clear
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { hostingController.view }

        /// Página doble (spread): acerca para llenar la altura y la posiciona en el borde de
        /// lectura, de modo que se lea como 2 mitades desplazándose en horizontal.
        func applyWideIfNeeded(_ scrollView: UIScrollView, aspect: CGFloat?, rtl: Bool) {
            guard let aspect, aspect > 1.2, !appliedWide, scrollView.bounds.width > 0 else { return }
            appliedWide = true
            DispatchQueue.main.async {
                let w = scrollView.bounds.width, h = scrollView.bounds.height
                // La imagen (fit-width) mide w/aspect de alto a zoom 1; este zoom la lleva a llenar h.
                let zoom = min(h * aspect / w, scrollView.maximumZoomScale)
                scrollView.setZoomScale(zoom, animated: false)
                scrollView.layoutIfNeeded()
                let offX = rtl ? max(0, scrollView.contentSize.width - w) : 0
                let offY = max(0, (scrollView.contentSize.height - h) / 2)
                scrollView.setContentOffset(CGPoint(x: offX, y: offY), animated: false)
            }
        }

        @objc func handleSingleTap(_ g: UITapGestureRecognizer) { onSingleTap() }

        @objc func handleDoubleTap(_ g: UITapGestureRecognizer) {
            guard let scrollView = g.view as? UIScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let point = g.location(in: hostingController.view)
                let size = scrollView.bounds.size
                let rect = CGRect(x: point.x - size.width / 6, y: point.y - size.height / 6,
                                  width: size.width / 3, height: size.height / 3)
                scrollView.zoom(to: rect, animated: true)
            }
        }
    }
}
