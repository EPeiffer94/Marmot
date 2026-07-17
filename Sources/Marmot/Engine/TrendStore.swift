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
    /// (Written as explicit loops — long tuple-generic chains time out the
    /// type checker on older Swift toolchains.)
    func movers(limit: Int = 3) -> [(name: String, delta: Int64)] {
        guard points.count >= 2 else { return [] }
        let current = points[points.count - 1].categorySizes
        let previous = points[points.count - 2].categorySizes

        var names: [String: String] = [:]
        for category in CleanupScanner.categories() {
            names[category.id] = category.name
        }

        var changes: [(name: String, delta: Int64)] = []
        for key in Set(current.keys).union(previous.keys) {
            let delta = (current[key] ?? 0) - (previous[key] ?? 0)
            if delta != 0 {
                changes.append((name: names[key] ?? key, delta: delta))
            }
        }
        changes.sort { abs($0.delta) > abs($1.delta) }
        return Array(changes.prefix(limit))
    }

    // MARK: - Forecast

    var forecastDaysUntilFull: Int? {
        Self.daysUntilFull(points: points)
    }

    /// Naive linear forecast: least-squares slope of disk usage over the last
    /// two weeks of snapshots, projected until free space hits zero. Returns
    /// nil without enough signal (≥5 points spanning ≥6 days, rising usage,
    /// and a result inside 1–365 days).
    static func daysUntilFull(points: [TrendPoint], now: Date = Date()) -> Int? {
        let recent = Array(points.suffix(14))
        guard recent.count >= 5,
              let first = recent.first, let last = recent.last,
              last.date.timeIntervalSince(first.date) >= 6 * 86_400,
              last.diskFree > 0 else { return nil }

        let base = first.date.timeIntervalSince1970
        let xs = recent.map { $0.date.timeIntervalSince1970 - base }
        let ys = recent.map { Double($0.diskUsed) }
        let n = Double(xs.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let sumXX = xs.reduce(0) { $0 + $1 * $1 }
        let denominator = n * sumXX - sumX * sumX
        guard denominator != 0 else { return nil }

        let slope = (n * sumXY - sumX * sumY) / denominator // bytes/second
        guard slope > 0 else { return nil }

        let days = Int(Double(last.diskFree) / slope / 86_400)
        return (1...365).contains(days) ? days : nil
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
