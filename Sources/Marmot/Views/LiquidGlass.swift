import SwiftUI

/// Liquid Glass (macOS 26+) with a graceful fallback everywhere else.
///
/// Two gates, and both are necessary:
///
/// 1. `#if compiler(>=6.2)` — `glassEffect` only EXISTS in the macOS 26 SDK
///    (shipped with Xcode 26 / Swift 6.2). On an older toolchain the symbol
///    is unknown, so `#available` alone would still fail to compile. This
///    keeps the project building on older CI runners and contributor Macs.
///
/// 2. `if #available(macOS 26.0, *)` — runtime gate, so the macOS 13 floor
///    is preserved: older systems get the material look they always had.
///
/// Deliberately applied only to Marmot's *floating* surfaces (toast, drop
/// overlay, command palette). Apple's guidance is that Liquid Glass belongs
/// to the controls layer floating above content — putting it behind dense
/// data hurts legibility, so the dashboard cards and tables keep their
/// pastel washes.
extension View {

    /// Liquid Glass on macOS 26+, `.regularMaterial` below it.
    @ViewBuilder
    func marmotGlass<S: Shape>(in shape: S) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
        #else
        self.background(.regularMaterial, in: shape)
        #endif
    }

    /// Tinted variant — used where the surface carries a semantic color.
    @ViewBuilder
    func marmotGlass<S: Shape>(in shape: S, tint: Color) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.tint(tint), in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
        #else
        self.background(.regularMaterial, in: shape)
        #endif
    }
}
