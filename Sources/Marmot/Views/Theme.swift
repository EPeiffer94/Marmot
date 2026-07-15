import SwiftUI

/// Marmot's pastel look: every module has a soft accent color, used for its
/// sidebar tile, start screen, and card washes. Colors are SwiftUI system
/// colors, so they adapt to light and dark mode automatically — the pastel
/// feel comes from low-opacity gradient washes rather than hardcoded tints.
enum Theme {

    /// Global accent — soft mint, applied at the window root.
    static let accent = Color.mint

    static func color(for section: SidebarSection) -> Color {
        switch section {
        case .dashboard: return .mint
        case .cleanup: return .teal
        case .autopilot: return .indigo
        case .uninstall: return .pink
        case .unusedApps: return .orange
        case .updates: return .blue
        case .duplicates: return .purple
        case .diskMap: return .cyan
        case .startup: return .green
        case .maintenance: return .yellow
        case .status: return .red
        case .history: return .gray
        }
    }

    /// Soft diagonal wash used behind tinted cards and tiles.
    static func wash(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color.opacity(0.16), color.opacity(0.05)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
