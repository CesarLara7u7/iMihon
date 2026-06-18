import SwiftUI

/// Raíz con pestañas. Equivale a `HomeScreen.kt` (Voyager TabNavigator) en Mihon.
/// Las 5 pestañas replican las de Mihon: Biblioteca, Recientes, Historial, Explorar, Más.
struct ContentView: View {
    enum Tab: Hashable {
        case library, updates, history, browse, preferences
    }

    @State private var selectedTab: Tab = .library
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            LibraryView()
                .tabItem { Label("Biblioteca", systemImage: "books.vertical") }
                .tag(Tab.library)

            UpdatesView()
                .tabItem { Label("Actualizaciones", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.updates)

            HistoryView()
                .tabItem { Label("Historial", systemImage: "clock") }
                .tag(Tab.history)

            BrowseView()
                .tabItem { Label("Explorar", systemImage: "compass.drawing") }
                .tag(Tab.browse)

            MoreView()
                .tabItem { Label("Preferencias", systemImage: "slider.horizontal.3") }
                .tag(Tab.preferences)
        }
        // Acento dinámico: leer aquí re-tinta toda la app al cambiarlo en Personalización.
        .tint(Color.mihonAccent)
        .preferredColorScheme(settings.colorScheme)
        .onAppear { applyNavBarTitleColor() }
        .onChange(of: settings.accentHex) { _, _ in applyNavBarTitleColor() }
    }

    /// Tiñe los títulos de navegación (Biblioteca, Recientes…) con el tono OSCURO del acento,
    /// en vez del negro sólido del sistema. Conserva el fondo (Liquid Glass) del sistema.
    private func applyNavBarTitleColor() {
        let color = UIColor(Color.mihonAccentText)
        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        standard.titleTextAttributes = [.foregroundColor: color]
        standard.largeTitleTextAttributes = [.foregroundColor: color]

        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        edge.titleTextAttributes = [.foregroundColor: color]
        edge.largeTitleTextAttributes = [.foregroundColor: color]

        let bar = UINavigationBar.appearance()
        bar.standardAppearance = standard
        bar.compactAppearance = standard
        bar.scrollEdgeAppearance = edge
    }
}

#Preview {
    ContentView()
}
