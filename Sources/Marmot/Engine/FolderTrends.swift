import Foundation

/// Per-root history of top-level folder sizes, recorded on each Disk Map
/// scan. Diffing the two most recent snapshots answers "what grew?" at the
/// folder level — the thing you actually want to know when the disk fills up.
final class FolderTrends {

    static let shared = FolderTrends()

    struct Snapshot: Codable {
        let date: Date
        let sizes: [String: Int64]
    }

    struct Movers {
        let since: Date
        let changes: [(name: String, delta: Int64)]
    }

    /// Ignore day-to-day noise below this delta.
    static let minDelta: Int64 = 50 * 1024 * 1024
    static let maxSnapshotsPerRoot = 30
    static let maxFoldersPerSnapshot = 48

    private var snapshots: [String: [Snapshot]] = [:]

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Marmot", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("foldertrends.json")
    }

    private init() {
        load()
    }

    /// Records the top-level folder sizes for a scan root (newest scan of the
    /// day wins).
    func record(root: String, children: [FileNode]) {
        var sizes: [String: Int64] = [:]
        for child in children where !child.name.hasPrefix("(") { // skip synthetic nodes
            sizes[child.name] = child.sizeBytes
            if sizes.count >= Self.maxFoldersPerSnapshot { break }
        }
        var list = (snapshots[root] ?? []).filter {
            !Calendar.current.isDate($0.date, inSameDayAs: Date())
        }
        list.append(Snapshot(date: Date(), sizes: sizes))
        snapshots[root] = Array(list.suffix(Self.maxSnapshotsPerRoot))
        save()
    }

    /// Roots that have enough history for Time Travel (≥2 snapshots).
    var rootsWithHistory: [String] {
        snapshots.filter { $0.value.count >= 2 }.keys.sorted()
    }

    /// Full snapshot history for one root, oldest first.
    func history(for root: String) -> [Snapshot] {
        snapshots[root] ?? []
    }

    /// Biggest folder-size changes between the two latest snapshots of a root.
    /// (Explicit loops — see TrendStore.movers for why.)
    func movers(root: String, limit: Int = 4) -> Movers? {
        guard let list = snapshots[root], list.count >= 2 else { return nil }
        let current = list[list.count - 1].sizes
        let previous = list[list.count - 2].sizes

        var changes: [(name: String, delta: Int64)] = []
        for key in Set(current.keys).union(previous.keys) {
            let delta = (current[key] ?? 0) - (previous[key] ?? 0)
            if abs(delta) >= Self.minDelta {
                changes.append((name: key, delta: delta))
            }
        }
        guard !changes.isEmpty else { return nil }
        changes.sort { abs($0.delta) > abs($1.delta) }
        return Movers(since: list[list.count - 2].date, changes: Array(changes.prefix(limit)))
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        snapshots = (try? decoder.decode([String: [Snapshot]].self, from: data)) ?? [:]
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshots) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
