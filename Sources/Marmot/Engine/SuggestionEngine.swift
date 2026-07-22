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
                        diskTotal: Int64,
                        historyEntries: [LogEntry] = [],
                        hasAutopilotRules: Bool = true) -> [Suggestion] {
        var suggestions: [Suggestion] = []

        // Habit detection: repeated manual cleaning with no rules set up.
        if let nudge = habitNudge(entries: historyEntries,
                                  hasAutopilotRules: hasAutopilotRules) {
            suggestions.append(nudge)
        }

        // Disk nearly full — leads the list, and points at the biggest wins
        // (Big Files) rather than just describing the problem.
        if diskTotal > 0, Double(diskFree) / Double(diskTotal) < 0.1 {
            suggestions.append(Suggestion(
                icon: "exclamationmark.triangle.fill",
                text: "Disk is over 90% full — only \(ByteFormat.string(diskFree)) left. Hunt the biggest wins",
                target: .bigFiles))
        }

        // Trash honesty: trash-first cleaning frees nothing until the Trash
        // empties. Surface what Marmot moved there that's still sitting.
        let lingering = trashLingeringBytes(entries: historyEntries)
        if lingering > 500_000_000 {
            suggestions.append(Suggestion(
                icon: "trash.circle",
                text: "\(ByteFormat.string(lingering)) Marmot cleaned is still in the Trash — space frees when it empties",
                target: .cleanup))
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

    /// Bytes Marmot moved to the Trash that are STILL there — the file-exists
    /// check makes this accurate after partial or full Trash emptying.
    static func trashLingeringBytes(entries: [LogEntry],
                                    fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> Int64 {
        entries
            .filter {
                !$0.dryRun
                    && $0.outcome == ItemOutcome.done.rawValue
                    && $0.action == ChangeAction.moveToTrash.rawValue
            }
            .reduce(Int64(0)) { total, entry in
                guard let trashed = entry.trashedTo, fileExists(trashed) else { return total }
                return total + entry.sizeBytes
            }
    }

    /// If the user manually cleaned on 3+ separate days in the last month and
    /// has no enabled Autopilot rules, gently point at Autopilot.
    static func habitNudge(entries: [LogEntry],
                           hasAutopilotRules: Bool,
                           now: Date = Date()) -> Suggestion? {
        guard !hasAutopilotRules else { return nil }
        let cutoff = now.addingTimeInterval(-30 * 86_400)
        let cleaningDays = Set(entries
            .filter {
                $0.source == "Cleanup" && !$0.dryRun
                    && $0.outcome == ItemOutcome.done.rawValue
                    && $0.date > cutoff
            }
            .map { Calendar.current.startOfDay(for: $0.date) })
        guard cleaningDays.count >= 3 else { return nil }
        return Suggestion(
            icon: "clock.badge.checkmark",
            text: "You've cleaned manually on \(cleaningDays.count) days this month — Autopilot can do it on a schedule",
            target: .autopilot)
    }
}
