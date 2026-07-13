import Foundation

struct TrendPoint: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let diskTotal: Int64
    let diskFree: Int64
    let junkTotal: Int64
    /// Cleanup category id → size at scan time, for "what changed" diffing.
    let categorySizes: [String: Int64]

    var diskUsed: Int64 { diskTotal - diskFree }
}

/// Persists one storage snapshot per day (newest scan wins), capped at a
/// year. Powers the Dashboard trends chart and the category movers list.
final class TrendStore: ObservableObject {

    static let shared = TrendStore()
    static let maxPoints = 365

    @Published private(set) var points: [TrendPoint] = []

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Marmot", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("trends.json")
    }

    private init() {
        load()
    }

    /// Records a snapshot; called after each completed cleanup scan.
    func record(junkTotal: Int64, categorySizes: [String: Int64]) {
        var total: Int64 = 0
        var free: Int64 = 0
        if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys:
            [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            total = Int64(values.volumeTotalCapacity ?? 0)
            free = values.volumeAvailableCapacityForImportantUsage ?? 0
        }
        let point = TrendPoint(date: Date(), diskTotal: total, diskFree: free,
                               junkTotal: junkTotal, categorySizes: categorySizes)
        var updated = points.filter {
            !Calendar.current.isDate($0.date, inSameDayAs: point.date)
        }
        updated.append(point)
        points = Array(updated.suffix(Self.maxPoints))
        save()
    }

    /// Category size changes between the two most recent snapshots,
    /// biggest absolute movers first.
    func movers(limit: Int = 3) -> [(name: String, delta: Int64)] {
        guard points.count >= 2 else { return [] }
        let current = points[points.count - 1].categorySizes
        let previous = points[points.count - 2].categorySizes
        let names = Dictionary(uniqueKeysWithValues: CleanupScanner.categories().map { ($0.id, $0.name) })
        return Set(current.keys).union(previous.keys)
            .map { key in
                (name: names[key] ?? key,
                 delta: (current[key] ?? 0) - (previous[key] ?? 0))
            }
            .filter { $0.delta != 0 }
            .sorted { abs($0.delta) > abs($1.delta) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        points = (try? decoder.decode([TrendPoint].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(points) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
