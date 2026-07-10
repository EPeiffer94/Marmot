import Foundation

/// All UserDefaults keys in one place — no scattered string literals.
enum Prefs {
    static let hudEnabled = "marmot.hudEnabled"
    static let defaultDryRun = "marmot.defaultDryRun"
    static let onboarded = "marmot.onboarded"
    static let whitelist = "marmot.whitelist"
    static let purgePaths = "marmot.purgePaths"
}
