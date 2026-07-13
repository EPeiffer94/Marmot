import Foundation

struct Suggestion: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    let target: SidebarSection
}

/// Connects the dots across modules and surfaces the handful of things worth
/// acting on right now. Read-only: every suggestion just navigates somewhere.
enum SuggestionEngine {

    /// Heavy-ish work (shell call, directory listing) — run off the main thread.
    static func compute(categories: [CleanupCategory],
                        apps: [InstalledApp],
                        diskFree: Int64,
                        diskTotal: Int64) -> [Suggestion] {
        var suggestions: [Suggestion] = []

        // Disk nearly full — leads the list when true.
        if diskTotal > 0, Double(diskFree) / Double(diskTotal) < 0.1 {
            suggestions.append(Suggestion(
                icon: "exclamationmark.triangle.fill",
                text: "Disk is over 90% full — only \(ByteFormat.string(diskFree)) left",
                target: .diskMap))
        }

        // Oversized cleanup categories.
        for category in categories where category.size > 2_000_000_000 && category.id != "trash" {
            suggestions.append(Suggestion(
                icon: category.icon,
                text: "\(category.name) holds \(ByteFormat.string(category.size))",
                target: .cleanup))
        }
        if let trash = categories.first(where: { $0.id == "trash" }), trash.size > 1_000_000_000 {
            suggestions.append(Suggestion(
                icon: "trash",
                text: "Your Trash holds \(ByteFormat.string(trash.size))",
                target: .cleanup))
        }

        // Apps untouched for a year.
        let cutoff = Calendar.current.date(byAdding: .month, value: -12, to: Date()) ?? Date()
        let unused = apps.filter {
            ($0.lastUsed ?? .distantPast) < cutoff && $0.bundleID.lowercased() != "dev.marmot.app"
        }
        if unused.count >= 2 {
            let size = unused.reduce(Int64(0)) { $0 + $1.sizeBytes }
            suggestions.append(Suggestion(
                icon: "hourglass",
                text: "\(unused.count) apps untouched for a year (\(ByteFormat.string(size)))",
                target: .unusedApps))
        }

        // Crowded login.
        let agents = StartupEngine.agents(in: SafetyRules.home + "/Library/LaunchAgents",
                                          kind: .userAgent)
        if agents.count >= 5 {
            suggestions.append(Suggestion(
                icon: "power",
                text: "\(agents.count) launch agents start at login",
                target: .startup))
        }

        // Local Time Machine snapshots.
        if Shell.exists("/usr/bin/tmutil") {
            let output = Shell.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"], timeout: 10)
            let count = output.stdout.split(separator: "\n")
                .filter { $0.contains("com.apple.TimeMachine") }.count
            if count >= 3 {
                suggestions.append(Suggestion(
                    icon: "clock.arrow.2.circlepath",
                    text: "\(count) local Time Machine snapshots may hold hidden space",
                    target: .maintenance))
            }
        }

        return Array(suggestions.prefix(5))
    }
}
