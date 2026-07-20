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

        guard let dup = strdup(root) else { return [] }
        let argv = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: 2)
        argv[0] = dup
        argv[1] = nil
        defer {
            free(dup)
            argv.deallocate()
        }
        guard let fts = fts_open(argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return [] }
        defer { fts_close(fts) }

        var seen = 0
        while let entry = fts_read(fts) {
            if isCancelled { break }
            let info = Int32(entry.pointee.fts_info)
            let path = String(cString: entry.pointee.fts_path)

            if info == FTS_D {
                seen += 1
                if seen % 256 == 0 { onProgress?(path) }
                // Never look inside app bundles, libraries, or cloud folders.
                let ext = ((path as NSString).lastPathComponent as NSString)
                    .pathExtension.lowercased()
                if DuplicateEngine.skipExtensions.contains(ext)
                    || DiskScanner.cloudRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
                    _ = fts_set(fts, entry, FTS_SKIP)
                }
                continue
            }

            guard info == FTS_F, let st = entry.pointee.fts_statp else { continue }
            let size = Int64(st.pointee.st_size)
            guard size >= Self.floorSize else { continue }
            results.append(BigFile(
                path: path,
                sizeBytes: size,
                modified: Date(timeIntervalSince1970: TimeInterval(st.pointee.st_mtimespec.tv_sec))))
            foundBytes += size
            onFound?(results.count, foundBytes)
        }
        return results.sorted { $0.sizeBytes > $1.sizeBytes }
    }
}
