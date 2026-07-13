import Foundation

/// All UserDefaults keys in one place — no scattered string literals.
enum Prefs {
    static let hudEnabled = "marmot.hudEnabled"
    static let defaultDryRun = "marmot.defaultDryRun"
    static let onboarded = "marmot.onboarded"
    static let whitelist = "marmot.whitelist"
    static let purgePaths = "marmot.purgePaths"
    /// GB threshold for the menu bar junk alert; 0 = off.
    static let junkAlertGB = "marmot.junkAlertGB"
    /// Unix timestamp of the last junk notification (24h debounce).
    static let junkAlertNotifiedAt = "marmot.junkAlertNotifiedAt"
}
