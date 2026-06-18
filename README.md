# Mihon iOS

Port de [Mihon](../mihon) (lector de manga Android) a iOS, reestructurado desde cero.
**Estrategia:** KMP (lógica compartida) + SwiftUI nativo.

---

## Estado actual: Fase 4 — Catálogo real vía backend Suwayomi ✅

La pestaña **Explorar** muestra **fuentes y manga reales** servidos por un backend
**Suwayomi-Server** (Tachidesk) que ejecuta las extensiones de Mihon. La app es su cliente
**GraphQL** (`SuwayomiClient` sobre Ktor). Portadas reales vía `AsyncImage`.

Probado de extremo a extremo: app iOS → Kotlin (Ktor GraphQL) → Suwayomi (localhost:4567)
→ extensión **MangaFire** → catálogo real (One Piece, Toriko, …).

### Levantar el servidor Suwayomi (requisito para Explorar)
```bash
mkdir -p ~/Suwayomi && cd ~/Suwayomi
ASSET=$(curl -sL https://api.github.com/repos/Suwayomi/Suwayomi-Server/releases/latest \
  | grep browser_download_url | grep -E 'Suwayomi-Server-.*\.jar"' | cut -d'"' -f4 | head -1)
curl -L -o Suwayomi-Server.jar "$ASSET"
/Users/b/Library/Java/JavaVirtualMachines/jbr-25.0.2/Contents/Home/bin/java -jar Suwayomi-Server.jar
```
Sirve en `http://localhost:4567`. En la app: **Más → Servidor Suwayomi** (URL por defecto ya
apunta ahí). Las extensiones/fuentes se gestionan en la WebUI del servidor o por GraphQL.

Capas previas: **red** Ktor/Darwin + cimientos WKWebView (Fase 3); **persistencia** SQLite
real con SQLDelight (Fase 2); modelos de dominio de Mihon (Fase 1).

```
mihon ios/
├── README.md
├── settings.gradle.kts / build.gradle.kts / gradle.properties   # proyecto Gradle KMP
├── gradlew + gradle/wrapper/                                     # Gradle 9.5.1
├── shared/                          # ★ Módulo Kotlin Multiplatform (solo iOS por ahora)
│   ├── build.gradle.kts             # targets iOS + plugin SQLDelight
│   └── src/
│       ├── commonMain/
│       │   ├── sqldelight/mihon/shared/database/   # mangas.sq, chapters.sq (esquema Mihon)
│       │   └── kotlin/mihon/shared/
│       │       ├── MihonShared.kt        # fachada que consume Swift
│       │       ├── Platform.kt           # expect platformName()
│       │       ├── domain/model/         # Manga, Chapter, TriState, UpdateStrategy (reales)
│       │       ├── domain/repository/    # LibraryRepository (interfaz)
│       │       ├── database/             # adapters, DatabaseFactory (expect), seeder
│       │       └── data/                 # DatabaseLibraryRepository (real) + SampleLibraryRepository (semilla)
│       └── iosMain/kotlin/.../           # Platform.ios.kt (UIDevice) + DatabaseFactory.ios.kt (NativeSqliteDriver)
└── iosApp/                         # App nativa iOS (SwiftUI)
    ├── MihonIOS.xcodeproj           # incluye build-phase que ejecuta ./gradlew embedAndSign
    └── MihonIOS/
        └── Models/MockData.swift    # ahora es un ADAPTADOR Kotlin→Swift (no datos hardcodeados)
        ├── MihonIOSApp.swift        # @main  (≈ App.kt / MainActivity)
        ├── ContentView.swift        # TabView raíz  (≈ HomeScreen.kt)
        ├── DesignSystem/Theme.swift # colores, portada placeholder (≈ presentation-core)
        ├── Models/                  # Manga, Chapter, MangaSource, MockData (≈ domain/model)
        └── Features/
            ├── Library/             # ≈ LibraryTab + LibraryScreenModel
            ├── Updates/             # ≈ UpdatesTab
            ├── History/             # ≈ HistoryTab
            ├── Browse/              # ≈ BrowseTab (fuentes + búsqueda global)
            ├── More/                # ≈ MoreTab + ajustes
            ├── MangaDetail/         # ≈ MangaScreen
            └── Reader/              # ≈ ReaderActivity + viewers
```

### Cómo abrir y ejecutar
> Requiere **Xcode 16+**. La compilación del framework Kotlin la dispara Xcode
> automáticamente (build-phase `./gradlew :shared:embedAndSignAppleFrameworkForXcode`).
> Gradle usa **JBR 25** vía `org.gradle.java.home` en `gradle.properties` (OpenJDK 26 es
> demasiado nuevo). La primera build descarga Kotlin/Native (~1 GB, una sola vez).

```bash
open "iosApp/MihonIOS.xcodeproj"
```
Selecciona un simulador de iPhone y pulsa ▶︎ (⌘R). Mínimo iOS 17.0.

Compilar solo el framework desde terminal:
```bash
./gradlew :shared:linkDebugFrameworkIosSimulatorArm64
```

---

## Hoja de ruta de migración

| Fase | Objetivo | Reutiliza de Mihon |
|------|----------|--------------------|
| **0. Esqueleto SwiftUI** ✅ | Navegación + pantallas con mock | — |
| **1. Módulo KMP `shared`** ✅ | Targets iOS + framework consumido por Xcode; modelos de dominio reales; datos servidos desde Kotlin | `domain/`, modelos |
| **2. Persistencia** ✅ | SQLDelight + `native-driver` iOS; tablas mangas/chapters; BD sembrada y persistida | `data/` (.sq, mappers) |
| **3. Red** ✅ | Ktor (motor Darwin) en commonMain; suspend→async en Swift; cimientos `WKWebView` | `source-api` (HttpSource) |
| **4. Fuentes** ✅ | Backend **Suwayomi** (GraphQL): conexión, listar fuentes y explorar catálogo real (MangaFire) con portadas | `source-api`, `source-local` |
| **5. Funcionalidad** 🚧 | ✅ detalle de fuente + capítulos reales + buscar + añadir a biblioteca + biblioteca desde servidor. Falta: descargas, historial, trackers | `domain/interactor`, trackers |
| **6. Lector real** ✅ | Carga páginas del servidor (`fetchChapterPages`), modo paginado con zoom (pellizco/doble toque) y controles | `ui/reader` (lógica) |

> Buscador, páginas del lector y catálogo online dependen de que la **red permita los dominios de las fuentes** (api.mangadex.org, etc.). En redes que los bloquean se muestra el error con "Reintentar"; el código es correcto y funciona en una red sin esos bloqueos. MangaDex ya está instalada en el servidor.

### Decisión pendiente: fuentes online
Las extensiones de Mihon son **APKs cargados dinámicamente** — imposible en iOS (App Store
prohíbe cargar código). Opciones:
- **(A) Backend tipo Tachidesk/Suwayomi** — un servidor ejecuta las extensiones; la app iOS
  es cliente HTTP. Conserva el catálogo existente. *(recomendado)*
- **(B) Solo fuente local + trackers** — lee CBZ/EPUB locales; legal y aprobable en App Store.
- **(C) Fuentes nativas en el binario** — inviable a escala.

Se resolverá al llegar a la Fase 4.

---

## Bloqueos conocidos de portabilidad (de Mihon Android)
- `android.webkit.WebView` → `WKWebView` (Cloudflare, motor JS).
- SAF / `UniFile` (scoped storage) → `FileManager` (sandbox iOS).
- `WorkManager` (tareas en background) → `BGTaskScheduler`.
- Notificaciones, permisos, cookies → APIs nativas de iOS.
- Carga dinámica de extensiones → ver "Decisión pendiente".
