import SwiftUI

/// Marmot's pastel look: every module has a soft accent color, used for its
/// sidebar tile, start screen, and card washes. Colors are SwiftUI system
/// colors, so they adapt to light and dark mode automatically — the pastel
/// feel comes from low-opacity gradient washes rather than hardcoded tints.
enum Theme {

    /// The user's chosen accent, or nil for the default mixed-pastel scheme
    /// (mint, green, pink, and blue, each module wearing its own).
    static var customAccent: Color? {
        named(UserDefaults.standard.string(forKey: Prefs.accent) ?? "")
    }

    /// Global accent — soft mint unless the user picked one in Settings.
    static var accent: Color { customAccent ?? .mint }

    /// Route every module tint through this: the module's own pastel by
    /// default, or the user's chosen accent app-wide when one is set.
    static func tint(_ defaultColor: Color) -> Color {
        customAccent ?? defaultColor
    }

    static let accentChoices: [(name: String, color: Color)] = [
        ("mint", .mint), ("green", .green), ("teal", .teal),
        ("cyan", .cyan), ("blue", .blue), ("pink", .pink)
    ]

    static func named(_ name: String) -> Color? {
        accentChoices.first { $0.name == name }?.color
    }

    /// Palette is deliberately restricted to pink, green, blue (and their
    /// soft relatives mint/teal/cyan) over white — Marmot's signature scheme.
    static func color(for section: SidebarSection) -> Color {
        if let custom = customAccent { return custom }
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
