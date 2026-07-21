import Foundation
import Darwin

struct BigFile: Identifiable {
    let id = UUID()
    let path: String
    let sizeBytes: Int64
    let modified: Date

    var name: String { (path as NSString).lastPathComponent }
    var directory: String { (path as NSString).deletingLastPathComponent }
}

/// Finds large files anywhere under a root — the classic "Large & Old"
/// premium feature. One fts pass; size and modification date come free
/// from the traversal's stat data.
final class BigFileScanner {

    /// Everything at or above this is collected; the view filters higher
    /// thresholds and ages in memory so changing filters never rescans.
    static let floorSize: Int64 = 100 * 1024 * 1024

    var isCancelled = false
    var onProgress: ((String) -> Void)?
    /// Running tally: (files found so far, total bytes so far).
    var onFound: ((Int, Int64) -> Void)?

    func scan(root: String) -> [BigFile] {
        var results: [BigFile] = []
        var foundBytes: Int64 = 0
        var seen = 0

        FTSWalker.walk(
            root: root,
            isCancelled: { self.isCancelled },
            directoryPre: { path, _, _ in
                seen += 1
                if seen % 256 == 0 { self.onProgress?(path) }
                // Never look inside app bundles, libraries, or cloud folders.
                let ext = ((path as NSString).lastPathComponent as NSString)
                    .pathExtension.lowercased()
                if DuplicateEngine.skipExtensions.contains(ext)
                    || DiskScanner.cloudRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
                    return .skip
                }
                return .descend
            },
            file: { path, _, st in
                let size = Int64(st.pointee.st_size)
                guard size >= Self.floorSize else { return }
                results.append(BigFile(
                    path: path,
                    sizeBytes: size,
                    modified: Date(timeIntervalSince1970: TimeInterval(st.pointee.st_mtimespec.tv_sec))))
                foundBytes += size
                self.onFound?(results.count, foundBytes)
            })
        return results.sorted { $0.sizeBytes > $1.sizeBytes }
    }
}
