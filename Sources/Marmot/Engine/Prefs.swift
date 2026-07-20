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
    /// Honor-system "I already support Marmot" — hides the gentle nudge.
    static let supporter = "marmot.supporter"
    /// Archive app + data to a zip before uninstalling.
    static let timeCapsule = "marmot.timeCapsule"
    /// Watchtower cadence in days (0 = off).
    static let watchtowerDays = "marmot.watchtowerDays"
    /// Unix timestamp of the last Watchtower check.
    static let watchtowerLastCheck = "marmot.watchtowerLastCheck"
    /// Last selected sidebar section — restored on launch.
    static let lastSection = "marmot.lastSection"
    /// Startup Sentinel: notify when new launch agents/daemons appear.
    static let sentinelEnabled = "marmot.sentinelEnabled"
    /// Startup Sentinel's baseline of known launchd plist paths.
    static let sentinelKnown = "marmot.sentinelKnown"
    /// Accent color name (pink/green/blue/mint/teal/cyan); empty = default.
    static let accent = "marmot.accent"
}
