import SwiftUI

/// Marmot's pastel look: every module has a soft accent color, used for its
/// sidebar tile, start screen, and card washes. Colors are SwiftUI system
/// colors, so they adapt to light and dark mode automatically — the pastel
/// feel comes from low-opacity gradient washes rather than hardcoded tints.
enum Theme {

    /// A multi-colored theme: an accent for controls plus a set of pastels
    /// cycled across modules, tiles, and cards. Never monochrome — variety
    /// is part of Marmot's personality.
    struct Palette {
        let name: String
        let accent: Color
        let colors: [Color]
    }

    /// Selectable themes. "Classic" (the default, when no theme is stored)
    /// is the original hand-tuned mint/green/pink/blue scheme.
    static let palettes: [Palette] = [
        Palette(name: "Ocean", accent: .blue,
                colors: [.blue, .cyan, .teal, .mint, .indigo]),
        Palette(name: "Bubblegum", accent: .pink,
                colors: [.pink, .purple, .indigo, .blue]),
        Palette(name: "Meadow", accent: .green,
                colors: [.green, .mint, .teal, .cyan]),
        Palette(name: "Sorbet", accent: .orange,
                colors: [.pink, .orange, .yellow, .mint])
    ]

    static func palette(named name: String) -> Palette? {
        palettes.first { $0.name == name }
    }

    /// The active theme, or nil for Classic. Unknown stored values (e.g.
    /// pre-2.9 single-color names) fall back to Classic gracefully.
    static var current: Palette? {
        palette(named: UserDefaults.standard.string(forKey: Prefs.accent) ?? "")
    }

    /// Control accent — soft mint in Classic, the theme's accent otherwise.
    static var accent: Color { current?.accent ?? .mint }

    /// Slot-based color for non-module surfaces (dashboard cards etc.):
    /// the hand-tuned classic color by default, or a stable position in the
    /// active theme's cycle so neighboring cards stay varied.
    static func slot(_ index: Int, classic: Color) -> Color {
        guard let palette = current else { return classic }
        return palette.colors[index % palette.colors.count]
    }

    /// Palette is deliberately restricted to soft pastels over white —
    /// Marmot's signature scheme. Classic assigns each module its own color;
    /// themes cycle their colors across the sidebar in order.
    static func color(for section: SidebarSection) -> Color {
        if let palette = current {
            let index = SidebarSection.allCases.firstIndex(of: section) ?? 0
            return palette.colors[index % palette.colors.count]
        }
        switch section {
        case .dashboard: return .mint
        case .cleanup: return .green
        case .autopilot: return .blue
        case .uninstall: return .pink
        case .unusedApps: return .pink
        case .updates: return .blue
        case .duplicates: return .pink
        case .bigFiles: return .blue
        case .diskMap: return .cyan
        case .startup: return .green
        case .maintenance: return .teal
        case .status: return .blue
        case .history: return .mint
        case .settings: return .gray
        }
    }

    /// Soft diagonal wash used behind tinted cards and tiles.
    static func wash(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color.opacity(0.16), color.opacity(0.05)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
