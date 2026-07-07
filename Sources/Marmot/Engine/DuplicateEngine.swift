import Foundation
import CryptoKit

struct DuplicateFile: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let sizeBytes: Int64
    let modified: Date
    var name: String { (path as NSString).lastPathComponent }
    var directory: String { (path as NSString).deletingLastPathComponent }
}

struct DuplicateGroup: Identifiable {
    let id = UUID()
    let sizeBytes: Int64
    /// Sorted newest-first; the first file is the default "keeper".
    let files: [DuplicateFile]
    var wastedBytes: Int64 { sizeBytes * Int64(max(files.count - 1, 0)) }
}

/// Finds files with identical content: candidates are grouped by exact size,
/// then verified with SHA-256 (full content for small files, head/middle/tail
/// chunks for large ones).
final class DuplicateEngine {

    static let minFileSize: Int64 = 1024 * 1024 // 1 MB
    static let skipExtensions: Set<String> = [
        "app", "framework", "bundle", "xcodeproj", "lrdata",
        "photoslibrary", "musiclibrary", "aplibrary", "tvlibrary",
        "imovielibrary", "fcpbundle"
    ]

    var isCancelled = false
    var onProgress: ((String) -> Void)?

    func scan(roots: [String]) -> [DuplicateGroup] {
        var bySize: [Int64: [String]] = [:]
        let fm = FileManager.default

        for root in roots {
            guard let enumerator = fm.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                if isCancelled { return [] }
                let path = url.path
                if DiskScanner.cloudRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
                    enumerator.skipDescendants()
                    continue
                }
                if Self.skipExtensions.contains(url.pathExtension.lowercased()) {
                    enumerator.skipDescendants()
                    continue
                }
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      values.isRegularFile == true,
                      let size = values.fileSize,
                      Int64(size) >= Self.minFileSize else { continue }
                bySize[Int64(size), default: []].append(path)
            }
        }

        var groups: [DuplicateGroup] = []
        for (size, paths) in bySize where paths.count > 1 {
            if isCancelled { return [] }
            var byHash: [String: [DuplicateFile]] = [:]
            for path in paths {
                onProgress?(path)
                guard let key = Self.contentKey(path: path, size: size) else { continue }
                let modified = FileSizer.modificationDate(path) ?? .distantPast
                byHash[key, default: []].append(
                    DuplicateFile(path: path, sizeBytes: size, modified: modified))
            }
            for (_, files) in byHash where files.count > 1 {
                groups.append(DuplicateGroup(
                    sizeBytes: size,
                    files: files.sorted { $0.modified > $1.modified }))
            }
        }
        return groups.sorted { $0.wastedBytes > $1.wastedBytes }
    }

    /// SHA-256 over the file content. Files ≤ 4 MB are hashed in full;
    /// larger files are hashed via 1 MB chunks at head, middle, and tail
    /// (identical size + identical chunks is a reliable duplicate signal).
    static func contentKey(path: String, size: Int64) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunkSize = 1024 * 1024

        func readChunk(at offset: UInt64) -> Data? {
            do {
                try handle.seek(toOffset: offset)
                return try handle.read(upToCount: chunkSize)
            } catch {
                return nil
            }
        }

        if size <= Int64(4 * chunkSize) {
            var offset: UInt64 = 0
            while true {
                guard let data = readChunk(at: offset), !data.isEmpty else { break }
                hasher.update(data: data)
                offset += UInt64(data.count)
            }
            if offset == 0 { return nil }
        } else {
            let offsets: [UInt64] = [
                0,
                UInt64(size / 2),
                UInt64(max(size - Int64(chunkSize), 0))
            ]
            for offset in offsets {
                guard let data = readChunk(at: offset), !data.isEmpty else { return nil }
                hasher.update(data: data)
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
