import SwiftUI

/// Helpers para la estética **Liquid Glass** de iOS 26 con respaldo elegante en versiones
/// anteriores (target = iOS 17). En iOS 26 se usa `glassEffect`/estilos de botón de cristal;
/// antes, materiales translúcidos equivalentes.
extension View {

    /// Fondo de cristal líquido recortado a `shape` (barras, controles flotantes…).
    @ViewBuilder
    func liquidGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(AppSettings.shared.clearGlass ? .clear : .regular, in: shape)
        } else {
            background(AppSettings.shared.clearGlass ? AnyShapeStyle(.ultraThinMaterial)
                       : AnyShapeStyle(.regularMaterial), in: shape)
        }
    }

    /// Fondo de cristal interactivo (reacciona al toque) recortado a `shape`.
    @ViewBuilder
    func liquidGlassInteractive<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }

    /// Estilo de botón prominente de cristal (respeta el `tint`); respaldo a `.borderedProminent`.
    @ViewBuilder
    func glassProminentButton() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    /// Estilo de botón de cristal (sutil); respaldo a `.bordered`.
    @ViewBuilder
    func glassButton() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}
