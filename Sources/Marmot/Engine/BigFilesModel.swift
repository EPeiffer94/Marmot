import Foundation

/// Shared scan state for Big Files. Lives outside the view so results
/// survive sidebar navigation instead of vanishing on every switch —
/// reopening the tool shows the last scan instantly.
final class BigFilesModel: ObservableObject {

    static let shared = BigFilesModel()

    @Published var files: [BigFile] = []
    @Published var scanning = false
    @Published var scannedOnce = false
    @Published var progressPath = ""
    @Published var foundCount = 0
    @Published var foundBytes: Int64 = 0
    @Published var minSizeMB = 100
    @Published var minAgeDays = 0

    private var scanner: BigFileScanner?

    func cancel() {
        scanner?.isCancelled = true
    }

    func startScan() {
        scanning = true
        scannedOnce = true
        foundCount = 0
        foundBytes = 0
        let s = BigFileScanner()
        scanner = s
        s.onProgress = { path in
            DispatchQueue.main.async { self.progressPath = path }
        }
        s.onFound = { count, bytes in
            DispatchQueue.main.async {
                self.foundCount = count
                self.foundBytes = bytes
            }
        }
        Task { @MainActor in
            let found = await Task.detached(priority: .userInitiated) {
                s.scan(root: NSHomeDirectory())
            }.value
            self.files = found
            self.scanning = false
        }
    }
}
