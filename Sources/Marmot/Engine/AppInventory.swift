import Foundation

/// Shared, observable inventory of installed apps: lists fast (no sizes),
/// then fills sizes in parallel. One source of truth for the Uninstaller and
/// Unused Apps views, so the disk is only walked once.
final class AppInventory: ObservableObject {

    static let shared = AppInventory()

    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var loading = false
    private var loadedOnce = false

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
            self.apps = found
            self.loading = false

            await withTaskGroup(of: (String, Int64).self) { group in
                for app in found {
                    group.addTask { (app.id, FileSizer.size(of: app.path)) }
                }
                for await (id, size) in group {
                    if let index = self.apps.firstIndex(where: { $0.id == id }) {
                        self.apps[index] = self.apps[index].withSize(size)
                    }
                }
            }
        }
    }
}
