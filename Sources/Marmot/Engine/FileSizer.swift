import Foundation
import Darwin

/// Fast recursive size computation using allocated sizes.
/// Traversal uses the C `fts` API — several times faster than
/// FileManager.enumerator because it never allocates per-file objects.
enum FileSizer {

    static func size(of path: String) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return fileSize(URL(fileURLWithPath: path))
        }
        // Wide directories: measure immediate children in parallel.
        let children = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        if children.count >= 8 {
            var sizes = [Int64](repeating: 0, count: children.count)
            sizes.withUnsafeMutableBufferPointer { buffer in
                DispatchQueue.concurrentPerform(iterations: children.count) { index in
                    buffer[index] = serialSize(of: path + "/" + children[index])
                }
            }
            return sizes.reduce(0, +)
        }
        return serialSize(of: path)
    }

    /// Single-threaded recursive size (also handles plain files).
    /// fts-based; falls back to FileManager if fts can't open the path.
    static func serialSize(of path: String) -> Int64 {
        // fts keeps reading the argv array during the whole traversal, so it
        // must be stable heap memory — a Swift array passed with `&` is only
        // valid for the fts_open call itself and dangles afterwards.
        guard let dup = strdup(path) else { return foundationSize(of: path) }
        let argv = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: 2)
        argv[0] = dup
        argv[1] = nil
        defer {
            free(dup)
            argv.deallocate()
        }

        guard let fts = fts_open(argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else {
            return foundationSize(of: path)
        }
        defer { fts_close(fts) }

        var total: Int64 = 0
        while let entry = fts_read(fts) {
            let info = Int32(entry.pointee.fts_info)
            // Regular files and directory inodes, like `du`. FTS_PHYSICAL
            // never follows symlinks; FTS_XDEV never crosses volumes.
            if info == FTS_F || info == FTS_D {
                if let st = entry.pointee.fts_statp {
                    total += Int64(st.pointee.st_blocks) * 512
                }
            }
        }
        return total
    }

    /// Foundation fallback, used only when fts fails to open the path.
    static func foundationSize(of path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return fileSize(url)
        }
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard let en = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }
        for case let child as URL in en {
            if let values = try? child.resourceValues(forKeys: Set(keys)),
               values.isRegularFile == true {
                total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            }
        }
        return total
    }

    static func fileSize(_ url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        if let values = try? url.resourceValues(forKeys: keys) {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return 0
    }

    static func modificationDate(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}
