import Foundation

/// Shared scan state for the Duplicate Finder. Lives outside the view so
/// results, keeper choices, and scan roots survive sidebar navigation.
final class DuplicatesModel: ObservableObject {

    static let shared = DuplicatesModel()

    @Published var groups: [DuplicateGroup] = []
    @Published var keepers: [UUID: UUID] = [:]     // group id → file id to keep
    @Published var includedGroups: Set<UUID> = []
    @Published var scanning = false
    @Published var scannedOnce = false
    @Published var progressPath = ""
    @Published var phase: DuplicateEngine.ScanPhase?
    @Published var roots: [String] = [
        NSHomeDirectory() + "/Downloads",
        NSHomeDirectory() + "/Documents",
        NSHomeDirectory() + "/Desktop"
    ]

    private var engine: DuplicateEngine?

    var totalWasted: Int64 {
        groups.filter { includedGroups.contains($0.id) }.reduce(0) { $0 + $1.wastedBytes }
    }

    /// User's explicit choice wins; otherwise the smart-keeper heuristics.
    func keeperID(for group: DuplicateGroup) -> UUID? {
        keepers[group.id] ?? DuplicateEngine.preferredKeeper(among: group.files)?.id
    }

    func cancel() {
        engine?.isCancelled = true
    }

    func startScan() {
        scanning = true
        scannedOnce = true
        groups = []
        keepers = [:]
        includedGroups = []
        phase = nil
        let e = DuplicateEngine()
        engine = e
        e.onProgress = { path in
            DispatchQueue.main.async { self.progressPath = path }
        }
        e.onPhase = { p in
            DispatchQueue.main.async { self.phase = p }
        }
        let scanRoots = roots.filter { FileManager.default.fileExists(atPath: $0) }
        Task { @MainActor in
            let found = await Task.detached(priority: .userInitiated) { e.scan(roots: scanRoots) }.value
            if e.isCancelled {
                // Cancelled: return to the start screen, not a misleading
                // "no duplicates found" empty state.
                self.scannedOnce = false
            } else {
                self.groups = found
                self.includedGroups = Set(found.map(\.id))
            }
            self.phase = nil
            self.progressPath = ""
            self.scanning = false
        }
    }
}
