import Foundation

/// A node in the disk-usage tree used by the treemap.
final class FileNode: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    var sizeBytes: Int64
    var children: [FileNode]
    weak var parent: FileNode?

    init(name: String, path: String, isDirectory: Bool,
         sizeBytes: Int64 = 0, children: [FileNode] = []) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.sizeBytes = sizeBytes
        self.children = children
    }
}

struct LargeFile: Identifiable {
    let id = UUID()
    let path: String
    let sizeBytes: Int64
    var name: String { (path as NSString).lastPathComponent }
}

/// Builds a size tree for the treemap and collects the largest files.
final class DiskScanner {

    static let maxDepth = 6
    static let maxChildrenPerDir = 60
    static let largeFileThreshold: Int64 = 100 * 1024 * 1024

    /// Cloud-backed locations (OneDrive, Google Drive, Dropbox, iCloud Drive).
    /// Their contents are mostly placeholder files; enumerating them stalls on
    /// the network file provider, so they are skipped — unless the user
    /// explicitly chooses to scan a folder inside one.
    static let cloudRoots: [String] = [
        NSHomeDirectory() + "/Library/CloudStorage",
        NSHomeDirectory() + "/Library/Mobile Documents"
    ]

    private(set) var largeFiles: [LargeFile] = []
    var isCancelled = false
    var onProgress: ((String) -> Void)?
    private var skipCloud = true
    /// Guards `largeFiles` — top levels of the scan run in parallel.
    private let largeFilesLock = NSLock()

    func scan(root: String) -> FileNode {
        largeFiles = []
        // If the user deliberately picked a folder inside a cloud root,
        // honor that choice and scan it.
        let normalizedRoot = SafetyRules.normalize(root)
        skipCloud = !Self.cloudRoots.contains {
            normalizedRoot == $0 || normalizedRoot.hasPrefix($0 + "/")
        }
        let node = scanNode(path: root, depth: 0)
        largeFiles.sort { $0.sizeBytes > $1.sizeBytes }
        if largeFiles.count > 100 { largeFiles = Array(largeFiles.prefix(100)) }
        return node
    }

    private func scanNode(path: String, depth: Int) -> FileNode {
        let name = (path as NSString).lastPathComponent
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)

        if !isDir.boolValue {
            let size = FileSizer.fileSize(URL(fileURLWithPath: path))
            if size >= Self.largeFileThreshold {
                largeFilesLock.lock()
                largeFiles.append(LargeFile(path: path, sizeBytes: size))
                largeFilesLock.unlock()
            }
            return FileNode(name: name, path: path, isDirectory: false, sizeBytes: size)
        }

        if depth % 2 == 0 { onProgress?(path) }
        if isCancelled {
            return FileNode(name: name, path: path, isDirectory: true, sizeBytes: 0)
        }

        // Past maxDepth just sum sizes without keeping structure.
        if depth >= Self.maxDepth {
            let size = FileSizer.size(of: path)
            return FileNode(name: name, path: path, isDirectory: true, sizeBytes: size)
        }

        let childNames = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        var children: [FileNode] = []

        if depth <= 1 && childNames.count > 4 {
            // Fan the top levels out across all cores.
            var slots = [FileNode?](repeating: nil, count: childNames.count)
            slots.withUnsafeMutableBufferPointer { buffer in
                DispatchQueue.concurrentPerform(iterations: childNames.count) { index in
                    buffer[index] = self.childNode(named: childNames[index], parent: path, depth: depth)
                }
            }
            children = slots.compactMap { $0 }
        } else {
            for childName in childNames {
                if isCancelled { break }
                if let child = childNode(named: childName, parent: path, depth: depth) {
                    children.append(child)
                }
            }
        }

        let total = children.reduce(Int64(0)) { $0 + $1.sizeBytes }
        children.sort { $0.sizeBytes > $1.sizeBytes }
        // Collapse the long tail into an "other" node to bound memory.
        if children.count > Self.maxChildrenPerDir {
            let kept = Array(children.prefix(Self.maxChildrenPerDir))
            let restSize = children.dropFirst(Self.maxChildrenPerDir).reduce(Int64(0)) { $0 + $1.sizeBytes }
            var merged = kept
            if restSize > 0 {
                merged.append(FileNode(name: "(\(children.count - kept.count) smaller items)",
                                       path: path, isDirectory: true, sizeBytes: restSize))
            }
            children = merged
        }

        let node = FileNode(name: name.isEmpty ? path : name, path: path,
                            isDirectory: true, sizeBytes: total, children: children)
        children.forEach { $0.parent = node }
        return node
    }

    /// Builds the node for one directory entry, applying all skip rules.
    /// Thread-safe: called concurrently for the top scan levels.
    private func childNode(named childName: String, parent path: String, depth: Int) -> FileNode? {
        if isCancelled { return nil }
        // Skip firmlinked/system mounts that inflate results.
        if depth == 0 && path == "/" && (childName == "Volumes" || childName == "System") { return nil }
        let childPath = path == "/" ? "/" + childName : path + "/" + childName
        // Skip cloud-provider folders (placeholder files; scanning hangs).
        if skipCloud && Self.cloudRoots.contains(where: { childPath == $0 || childPath.hasPrefix($0 + "/") }) {
            return FileNode(name: childName + " (cloud — skipped)",
                            path: childPath, isDirectory: true, sizeBytes: 0)
        }
        // Don't follow symlinks (cheap lstat, no Foundation overhead).
        var sb = stat()
        guard lstat(childPath, &sb) == 0 else { return nil }
        if (sb.st_mode & S_IFMT) == S_IFLNK { return nil }
        return scanNode(path: childPath, depth: depth + 1)
    }
}
