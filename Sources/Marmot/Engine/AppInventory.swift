import Foundation

/// Shared, observable inventory of installed apps: lists fast (no sizes),
/// then fills sizes in parallel. One source of truth for the Uninstaller and
/// Unused Apps views, so the disk is only walked once.
///
/// Sizes are cached on disk keyed by bundle path + modification date, so
/// relaunches show them instantly. App updates replace the bundle (fresh
/// mtime) and invalidate their entry naturally.
final class AppInventory: ObservableObject {

    static let shared = AppInventory()

    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var loading = false
    private var loadedOnce = false

    private struct SizeCacheEntry: Codable {
        let mtime: TimeInterval
        let size: Int64
    }

    private var sizeCache: [String: SizeCacheEntry]

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Marmot", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("app-sizes.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.cacheURL),
           let cache = try? JSONDecoder().decode([String: SizeCacheEntry].self, from: data) {
            sizeCache = cache
        } else {
            sizeCache = [:]
        }
    }

    func loadIfNeeded() {
        if !loadedOnce { refresh() }
    }

    func refresh() {
        loadedOnce = true
        loading = true
        Task { @MainActor in
            let found = await Task.detached(priority: .userInitiated) {
                UninstallEngine.installedApps(computeSizes: false)
            }.value

            // Seed cached sizes immediately; only changed bundles recompute.
            var seeded = found
            var toCompute: [InstalledApp] = []
            for (index, app) in seeded.enumerated() {
                if let mtime = Self.bundleMTime(app.path),
                   let entry = sizeCache[app.path],
                   abs(entry.mtime - mtime) < 1 {
                    seeded[index] = app.withSize(entry.size)
                } else {
                    toCompute.append(app)
                }
            }
            self.apps = seeded
            self.loading = false

            await withTaskGroup(of: (String, Int64).self) { group in
                for app in toCompute {
                    group.addTask { (app.id, FileSizer.size(of: app.path)) }
                }
                for await (id, size) in group {
                    if let index = self.apps.firstIndex(where: { $0.id == id }) {
                        self.apps[index] = self.apps[index].withSize(size)
                        if let mtime = Self.bundleMTime(self.apps[index].path) {
                            self.sizeCache[self.apps[index].path] =
                                SizeCacheEntry(mtime: mtime, size: size)
                        }
                    }
                }
            }
            self.saveCache(keeping: Set(found.map(\.path)))
        }
    }

    private static func bundleMTime(_ path: String) -> TimeInterval? {
        FileSizer.modificationDate(path)?.timeIntervalSince1970
    }

    /// Persist, pruning entries for apps that no longer exist.
    private func saveCache(keeping installed: Set<String>) {
        sizeCache = sizeCache.filter { installed.contains($0.key) }
        if let data = try? JSONEncoder().encode(sizeCache) {
            try? data.write(to: Self.cacheURL, options: .atomic)
        }
    }
}
