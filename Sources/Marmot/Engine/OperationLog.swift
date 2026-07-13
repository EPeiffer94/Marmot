import Foundation

/// Append-only JSONL log of everything Marmot did (or would have done in a dry
/// run). Mirrors `mo history`. Stored in ~/Library/Application Support/Marmot/.
struct LogEntry: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let source: String
    let dryRun: Bool
    let action: String
    let target: String
    let sizeBytes: Int64
    let outcome: String
    /// Trash destination for restorable items (absent in older log entries).
    var trashedTo: String? = nil
}

final class OperationLog {
    static let shared = OperationLog()

    private let queue = DispatchQueue(label: "marmot.oplog")
    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Marmot", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("operations.jsonl")
    }

    /// Rotation: when the log exceeds this size, keep only the newest entries.
    private static let maxLogBytes = 2_000_000
    private static let keepEntries = 4000

    func record(_ result: ExecutionResult, source: String) {
        queue.async {
            self.rotateIfNeeded()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var lines: [Data] = []
            for r in result.results {
                let entry = LogEntry(
                    date: result.finishedAt,
                    source: source,
                    dryRun: result.dryRun,
                    action: r.item.action.rawValue,
                    target: r.item.target,
                    sizeBytes: r.item.sizeBytes,
                    outcome: r.outcome.rawValue,
                    trashedTo: r.trashedTo
                )
                if let data = try? encoder.encode(entry) {
                    lines.append(data)
                }
            }
            guard !lines.isEmpty else { return }
            let blob = lines.map { String(data: $0, encoding: .utf8) ?? "" }
                .joined(separator: "\n") + "\n"
            if let handle = try? FileHandle(forWritingTo: self.fileURL) {
                handle.seekToEndOfFile()
                handle.write(blob.data(using: .utf8)!)
                try? handle.close()
            } else {
                try? blob.data(using: .utf8)?.write(to: self.fileURL)
            }
        }
    }

    func readAll() -> [LogEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return Array(text.split(separator: "\n").compactMap { line in
            try? decoder.decode(LogEntry.self, from: Data(line.utf8))
        }.reversed())
    }

    func clear() {
        queue.async { try? FileManager.default.removeItem(at: self.fileURL) }
    }

    /// Must be called on `queue`. Trims the JSONL file to the newest entries
    /// once it grows past the size cap, so it never balloons unbounded.
    private func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int,
              size > Self.maxLogBytes,
              let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n")
        guard lines.count > Self.keepEntries else { return }
        let trimmed = lines.suffix(Self.keepEntries).joined(separator: "\n") + "\n"
        try? trimmed.data(using: .utf8)?.write(to: fileURL, options: .atomic)
    }
}

// MARK: - Freed-space statistics (Dashboard report card)

struct FreedStats {
    var last7Days: Int64 = 0
    var last30Days: Int64 = 0
    var allTime: Int64 = 0
    var biggestRecent: LogEntry?
    var isEmpty: Bool { allTime == 0 }
}

extension OperationLog {
    /// Aggregates real (non-dry-run) removals from the history log.
    func freedStats(now: Date = Date()) -> FreedStats {
        let removals = readAll().filter {
            !$0.dryRun
                && $0.outcome == ItemOutcome.done.rawValue
                && ($0.action == ChangeAction.moveToTrash.rawValue
                    || $0.action == ChangeAction.deletePermanently.rawValue)
        }
        var stats = FreedStats()
        let week = now.addingTimeInterval(-7 * 86400)
        let month = now.addingTimeInterval(-30 * 86400)
        for entry in removals {
            stats.allTime += entry.sizeBytes
            if entry.date > month {
                stats.last30Days += entry.sizeBytes
                if let best = stats.biggestRecent {
                    if entry.sizeBytes > best.sizeBytes { stats.biggestRecent = entry }
                } else {
                    stats.biggestRecent = entry
                }
            }
            if entry.date > week {
                stats.last7Days += entry.sizeBytes
            }
        }
        return stats
    }
}
