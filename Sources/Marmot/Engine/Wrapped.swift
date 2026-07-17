import Foundation

struct WrappedStats {
    var totalFreed: Int64 = 0
    var itemCount: Int = 0
    var activeDays: Int = 0
    var autopilotFreed: Int64 = 0
    var topTool: (name: String, freed: Int64)?
    var biggest: (name: String, size: Int64)?
    var since: Date?

    var isEmpty: Bool { totalFreed == 0 }
}

/// Turns the history log into bragging rights.
enum Wrapped {

    static func stats(from entries: [LogEntry]) -> WrappedStats {
        let removals = entries.filter {
            !$0.dryRun
                && $0.outcome == ItemOutcome.done.rawValue
                && ($0.action == ChangeAction.moveToTrash.rawValue
                    || $0.action == ChangeAction.deletePermanently.rawValue)
        }
        var stats = WrappedStats()
        var bySource: [String: Int64] = [:]
        var days = Set<Date>()

        for entry in removals {
            stats.totalFreed += entry.sizeBytes
            stats.itemCount += 1
            bySource[entry.source, default: 0] += entry.sizeBytes
            days.insert(Calendar.current.startOfDay(for: entry.date))
            if entry.sizeBytes > (stats.biggest?.size ?? 0) {
                stats.biggest = ((entry.target as NSString).lastPathComponent, entry.sizeBytes)
            }
            if stats.since == nil || entry.date < stats.since! {
                stats.since = entry.date
            }
        }

        stats.activeDays = days.count
        stats.autopilotFreed = bySource["Autopilot"] ?? 0
        if let top = bySource.max(by: { $0.value < $1.value }) {
            stats.topTool = (top.key, top.value)
        }
        return stats
    }
}
