import Foundation

/// Turns natural-ish ⌘K queries into structured intents — entirely local,
/// no models, no network. "big old videos" → Big Files filters;
/// "uninstall slack" → the uninstaller with Slack selected.
enum IntentParser {

    struct BigFilesQuery: Equatable {
        var minSizeMB: Int
        var minAgeDays: Int
    }

    /// Size/age vocabulary → Big Files query, or nil if the words don't fit.
    static func bigFilesQuery(from raw: String) -> BigFilesQuery? {
        let query = raw.lowercased()
        var minSize: Int?
        var minAge: Int?

        // Explicit sizes: "500 mb", "2gb"
        if let range = query.range(of: #"(\d+)\s*(gb|mb)"#, options: .regularExpression) {
            let text = String(query[range])
            let digits = Int(text.filter(\.isNumber)) ?? 0
            minSize = text.contains("gb") ? digits * 1000 : digits
        } else if query.contains("huge") {
            minSize = 1000
        } else if query.contains("big") || query.contains("large") {
            minSize = 500
        }

        // Ages: "2 years", "6 months", or just "old"
        if let range = query.range(of: #"(\d+)\s*year"#, options: .regularExpression) {
            minAge = (Int(String(query[range]).filter(\.isNumber)) ?? 1) * 365
        } else if let range = query.range(of: #"(\d+)\s*month"#, options: .regularExpression) {
            minAge = (Int(String(query[range]).filter(\.isNumber)) ?? 6) * 30
        } else if query.contains("old") || query.contains("forgotten") {
            minAge = 180
        }

        guard minSize != nil || minAge != nil else { return nil }
        return BigFilesQuery(minSizeMB: minSize ?? 100, minAgeDays: minAge ?? 0)
    }

    /// "uninstall slack", "remove zoom", "reset spotify" → (reset?, app name)
    static func appAction(from raw: String) -> (reset: Bool, name: String)? {
        let query = raw.lowercased().trimmingCharacters(in: .whitespaces)
        for prefix in ["uninstall ", "remove ", "delete "] where query.hasPrefix(prefix) {
            let name = String(query.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return (reset: false, name: name) }
        }
        if query.hasPrefix("reset ") {
            let name = String(query.dropFirst("reset ".count)).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return (reset: true, name: name) }
        }
        return nil
    }
}
