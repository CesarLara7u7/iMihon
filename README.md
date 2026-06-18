# iMihon

Port nativo de [Mihon](../mihon) (lector de manga Android) a **iOS**, reescrito desde cero.
**Arquitectura:** Kotlin Multiplatform (lógica compartida) + **SwiftUI** nativo.

> **Sin servidor.** A diferencia del enfoque inicial (se evaluó y descartó un backend
> Suwayomi/Tachidesk), la app consulta las **APIs de las fuentes directamente** desde el
> módulo Kotlin. Las extensiones de Mihon son APKs de Android y no pueden ejecutarse en iOS,
> así que cada fuente se **reimplementa de forma nativa**.

---

## Fuentes soportadas

| Fuente | Acceso | Notas |
|--------|--------|-------|
| **MangaDex** | API JSON directa (`api.mangadex.org`) | Multi-idioma. UA neutro (su Cloudflare rechaza UA de navegador). |
| **MANGA Plus** (Shueisha) | API oficial con `format=json` | Oficial y SFW. Imágenes cifradas con **XOR** (se descifran en cliente). Solo libera primeros/últimos capítulos. |
| **Comick** | **WKWebView** (Cloudflare) | Capítulos completos, multi-idioma. Explorar + leer ✅; **búsqueda de texto no** (Cloudflare blinda `/api/search`). |
| **MangaFire** | **WKWebView** (Cloudflare) | Token `vrf` capturado del propio sitio; imágenes **barajadas** (se des-barajan con Core Graphics). Con búsqueda. |

### Cómo se sortea Cloudflare (Comick / MangaFire)
La pila TLS nativa (URLSession/Ktor) recibe el reto "Just a moment" de Cloudflare. La solución
es un **`WKWebView` oculto** (`WebViewFetcher` en Swift) que carga el sitio, resuelve el reto y
ejecuta las peticiones con `fetch()` en el contexto de la página (heredando cookies + huella TLS
real de WebKit). El módulo Kotlin define la interfaz `WebFetcher` y enruta por ahí las fuentes
protegidas. Las **imágenes** se bajan con `URLSession` (solo requieren `Referer`).

---

## Funcionalidades

- **Biblioteca local** (SQLDelight, migraciones hasta **v8**): favoritos, **categorías** con
  estanterías estilo Netflix (incl. **privadas** con palabra mágica + Face ID y **🔥 Tendencia**
  por tiempo de lectura), expandir/contraer estanterías.
- **Lector** paginado y **webtoon**: zoom persistente, filtros de color, prefetch, páginas dobles
  (spreads), **hápticas graduales** al cambiar de capítulo (adelante y atrás), indicador
  "Capítulo anterior", **scrubber lateral** en webtoon, mensajes de fin de capítulo.
- **Explorar**: catálogo por fuente con filtros y orden, **búsqueda global en streaming**
  (resultados por fuente conforme llegan, sigue en segundo plano al entrar a un manga), y
  **fuente predeterminada** (⭐) para Explorar/Actualizaciones.
- **Descargas** offline por capítulo/serie/selección, con reanudación y retención.
- **Historial**, **Actualizaciones recientes** (caché + auto-refresco), **progreso por capítulo**,
  marcar visto/no visto, marca **+18** (excluye de Historial/Actualizaciones), eliminar por
  completo un manga de todas las tablas.
- **Personalización**: acento dinámico, temas de fondo, patrones de emoji, partículas, Liquid
  Glass, claro/oscuro/sistema, modo una mano, tarjeta coleccionable (giroscopio).
- **Fuentes** (Preferencias): activar/desactivar por fuente o idioma, alerta de edad para +18.

---

## Estructura del proyecto

```
mihon ios/
├── settings.gradle.kts / build.gradle.kts / gradle.properties   # proyecto Gradle KMP
├── gradlew + gradle/wrapper/                                     # Gradle wrapper
├── shared/                          # ★ Módulo Kotlin Multiplatform (solo target iOS)
│   ├── build.gradle.kts             # targets iOS + Ktor + plugin SQLDelight
│   └── src/
│       ├── commonMain/
│       │   ├── sqldelight/mihon/shared/database/   # esquema (.sq) + migraciones (.sqm, v→8)
│       │   └── kotlin/mihon/shared/
│       │       ├── MihonShared.kt              # fachada que consume Swift
│       │       ├── source/                     # MangaSource + MangaDex/MangaPlus/Comick/MangaFire
│       │       │   ├── SourceRegistry.kt       # registro de fuentes/idiomas
│       │       │   └── WebFetcher.kt           # puente a WKWebView (Cloudflare)
│       │       └── data/                       # repos: favoritos, categorías, historial,
│       │                                       #   progreso, descargas, tiempo de lectura, nsfw…
│       └── iosMain/kotlin/.../                 # Platform.ios.kt + driver SQLDelight nativo
└── iosApp/                          # App nativa iOS (SwiftUI)
    ├── Info.plist                   # CFBundleDisplayName = iMihon, Face ID
    ├── MihonIOS.xcodeproj           # build-phase: ./gradlew embedAndSign del framework
    └── MihonIOS/
        ├── MihonIOSApp.swift        # @main; registra el WebViewFetcher
        ├── ContentView.swift        # TabView raíz (Biblioteca/Actualizaciones/Historial/Explorar/Preferencias)
        ├── Models/                  # AppSettings, MockData (adaptador Kotlin→Swift)
        ├── DesignSystem/            # Theme, AppTheme, ImageCache (descifrado XOR/barajado), Liquid Glass…
        └── Features/
            ├── Library/             # estanterías, modo una mano
            ├── Updates/ History/    # actualizaciones recientes / historial
            ├── Browse/              # Explorar, búsqueda, detalle, WebViewFetcher, cromo
            ├── More/                # Preferencias: Lectura, Personalización, Fuentes, Descargas
            └── Reader/              # lector paginado + webtoon
```

---

## Compilar y ejecutar

> Requiere **Xcode 16+**, mínimo **iOS 17.0**. Gradle usa **JBR 25** vía `org.gradle.java.home`
> en `gradle.properties` (OpenJDK 26 rompe Gradle/Kotlin). La primera build descarga
> Kotlin/Native (~1 GB, una sola vez). La compilación del framework Kotlin la dispara Xcode
> automáticamente (build-phase `./gradlew :shared:embedAndSignAppleFrameworkForXcode`).

```bash
open "iosApp/MihonIOS.xcodeproj"
```
Selecciona un simulador (o un iPhone) y pulsa ▶︎ (⌘R).

Compilar solo el framework desde terminal:
```bash
./gradlew :shared:linkDebugFrameworkIosSimulatorArm64
```

---

## Notas de portabilidad (de Mihon Android)
- `android.webkit.WebView` → `WKWebView` (usado para resolver Cloudflare en Comick/MangaFire).
- Carga dinámica de extensiones (APK) → **reimplementación nativa** de cada fuente.
- SAF / `UniFile` → `FileManager` (sandbox iOS). `WorkManager` → tareas iOS.
- `@Throws(Exception::class)` es **obligatorio** en toda función Kotlin llamada desde Swift con
  `try`/`await`: si no, una excepción aborta la app (SIGABRT) en vez de propagarse al `catch`.
```
