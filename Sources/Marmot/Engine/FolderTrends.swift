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
        let sizes = Dictionary(
            children
                .filter { !$0.name.hasPrefix("(") } // skip synthetic nodes
                .prefix(Self.maxFoldersPerSnapshot)
                .map { ($0.name, $0.sizeBytes) },
            uniquingKeysWith: { first, _ in first })
        var list = (snapshots[root] ?? []).filter {
            !Calendar.current.isDate($0.date, inSameDayAs: Date())
        }
        list.append(Snapshot(date: Date(), sizes: sizes))
        snapshots[root] = Array(list.suffix(Self.maxSnapshotsPerRoot))
        save()
    }

    /// Biggest folder-size changes between the two latest snapshots of a root.
    func movers(root: String, limit: Int = 4) -> Movers? {
        guard let list = snapshots[root], list.count >= 2 else { return nil }
        let current = list[list.count - 1].sizes
        let previous = list[list.count - 2].sizes
        let changes = Set(current.keys).union(previous.keys)
            .map { (name: $0, delta: (current[$0] ?? 0) - (previous[$0] ?? 0)) }
            .filter { abs($0.delta) >= Self.minDelta }
            .sorted { abs($0.delta) > abs($1.delta) }
            .prefix(limit)
        guard !changes.isEmpty else { return nil }
        return Movers(since: list[list.count - 2].date, changes: Array(changes))
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
