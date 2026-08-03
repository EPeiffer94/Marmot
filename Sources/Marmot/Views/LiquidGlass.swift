import SwiftUI

/// Liquid Glass surfaces.
///
/// Marmot's deployment target is macOS 26, so no runtime `#available` gate
/// is needed — but `glassEffect` only EXISTS in the macOS 26 SDK (Xcode 26 /
/// Swift 6.2). The `#if compiler` gate keeps the package parsing and
/// building on an older toolchain (a contributor's Mac, a stale CI image)
/// instead of failing on an unknown symbol; those builds simply fall back
/// to the material look.
///
/// Deliberately applied only to Marmot's *floating* surfaces (toast, drop
/// overlay, command palette). Apple's guidance is that Liquid Glass belongs
/// to the controls layer floating above content — putting it behind dense
/// data hurts legibility, so the dashboard cards and tables keep their
/// pastel washes.
extension View {

    @ViewBuilder
    func marmotGlass<S: Shape>(in shape: S) -> some View {
        #if compiler(>=6.2)
        self.glassEffect(.regular, in: shape)
        #else
        self.background(.regularMaterial, in: shape)
        #endif
    }

    /// Tinted variant — used where the surface carries a semantic color.
    @ViewBuilder
    func marmotGlass<S: Shape>(in shape: S, tint: Color) -> some View {
        #if compiler(>=6.2)
        self.glassEffect(.regular.tint(tint), in: shape)
        #else
        self.background(.regularMaterial, in: shape)
        #endif
    }
}
