import Foundation

/// Shared scan state for the Disk Map — the heaviest scan in the app, so
/// its tree survives sidebar navigation instead of being thrown away and
/// rebuilt on every visit.
final class DiskMapModel: ObservableObject {

    static let shared = DiskMapModel()

    @Published var rootNode: FileNode?
    @Published var currentNode: FileNode?
    @Published var largeFiles: [LargeFile] = []
    @Published var scanning = false
    @Published var progressPath = ""
    @Published var scanTarget = NSHomeDirectory()
    @Published var folderMovers: FolderTrends.Movers?

    private var scanner: DiskScanner?

    func cancel() {
        scanner?.isCancelled = true
    }

    func startScan() {
        scanning = true
        rootNode = nil
        currentNode = nil
        let target = scanTarget
        let s = DiskScanner()
        scanner = s
        s.onProgress = { path in
            DispatchQueue.main.async { self.progressPath = path }
        }
        Task { @MainActor in
            let tree = await Task.detached(priority: .userInitiated) { s.scan(root: target) }.value
            self.rootNode = tree
            self.currentNode = tree
            self.largeFiles = s.largeFiles
            self.scanning = false
            FolderTrends.shared.record(root: target, children: tree.children)
            self.folderMovers = FolderTrends.shared.movers(root: target)
        }
    }
}
