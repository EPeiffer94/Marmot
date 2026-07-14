import Foundation

/// Shared cleanup state: category scan results, persisted between launches so
/// every screen (Dashboard, Cleanup) shows numbers instantly and refreshes in
/// the background. The cache is display-only — applying a plan always
/// re-validates every path through SafetyRules at execution time.
final class CleanupModel: ObservableObject {

    static let shared = CleanupModel()

    @Published private(set) var categories: [CleanupCategory] = CleanupScanner.categories()
    @Published private(set) var scanning = false
    @Published private(set) var lastScan: Date?

    var scannedOnce: Bool { lastScan != nil }
    var totalFound: Int64 { categories.reduce(0) { $0 + $1.size } }
    var nonEmptyCategoryIDs: Set<String> {
        Set(categories.filter { !$0.items.isEmpty }.map(\.id))
    }

    private struct CachePayload: Codable {
        let date: Date
        let items: [String: [ChangeItem]]
    }

    private var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Marmot", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("scancache.json")
    }

    private init() {
        // Decode the cache off the main thread so launch stays instant;
        // apply() refuses stale data if a live scan beat it.
        let url = cacheURL
        Task.detached(priority: .utility) { [weak self] in
            guard let payload = Self.decodeCache(at: url) else { return }
            guard let self else { return }
            await MainActor.run { self.apply(payload) }
        }
    }

    private func apply(_ payload: CachePayload) {
        guard !scanning, lastScan == nil else { return }
        for index in categories.indices {
            categories[index].items = payload.items[categories[index].id] ?? []
        }
        lastScan = payload.date
    }

    // MARK: - Scanning

    func rescan() {
        guard !scanning else { return }
        scanning = true
        for index in categories.indices {
            categories[index].isScanning = true
        }
        Task { @MainActor in
            let base = CleanupScanner.categories()
            await withTaskGroup(of: (Int, [ChangeItem]).self) { group in
                for (index, category) in base.enumerated() {
                    group.addTask {
                        (index, CleanupScanner.scan(categoryID: category.id))
                    }
                }
                for await (index, items) in group {
                    self.categories[index].items = items
                    self.categories[index].isScanning = false
                }
            }
            self.scanning = false
            self.lastScan = Date()
            self.saveCache()
            TrendStore.shared.record(
                junkTotal: self.totalFound,
                categorySizes: Dictionary(uniqueKeysWithValues: self.categories.map { ($0.id, $0.size) }))
        }
    }

    // MARK: - Cache

    private static func decodeCache(at url: URL) -> CachePayload? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CachePayload.self, from: data)
    }

    private func saveCache() {
        var items: [String: [ChangeItem]] = [:]
        for category in categories {
            items[category.id] = category.items
        }
        let payload = CachePayload(date: lastScan ?? Date(), items: items)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(payload) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }
}
