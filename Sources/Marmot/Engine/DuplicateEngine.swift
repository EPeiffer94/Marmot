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
        // Size → (path, device:inode). The file ID lets us skip hardlinked
        // twins: removing one hardlink to the same file frees no space.
        var bySize: [Int64: [(path: String, fileID: String)]] = [:]
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
                var sb = stat()
                guard lstat(path, &sb) == 0 else { continue }
                bySize[Int64(size), default: []].append(
                    (path: path, fileID: "\(sb.st_dev):\(sb.st_ino)"))
            }
        }

        // Hash all same-size candidates in parallel — this is the slow part.
        // Within each size bucket, hardlinks to the same physical file are
        // collapsed to one entry first.
        var candidates: [(size: Int64, path: String)] = []
        for (size, entries) in bySize where entries.count > 1 {
            var seenIDs = Set<String>()
            let unique = entries.filter { seenIDs.insert($0.fileID).inserted }
            guard unique.count > 1 else { continue }
            candidates.append(contentsOf: unique.map { (size, $0.path) })
        }
        guard !candidates.isEmpty else { return [] }

        var keyed = [(key: String, file: DuplicateFile)?](repeating: nil, count: candidates.count)
        keyed.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: candidates.count) { index in
                if isCancelled { return }
                let candidate = candidates[index]
                onProgress?(candidate.path)
                guard let hash = Self.contentKey(path: candidate.path, size: candidate.size) else { return }
                buffer[index] = (
                    key: "\(candidate.size):\(hash)",
                    file: DuplicateFile(path: candidate.path,
                                        sizeBytes: candidate.size,
                                        modified: FileSizer.modificationDate(candidate.path) ?? .distantPast))
            }
        }
        if isCancelled { return [] }

        var byKey: [String: [DuplicateFile]] = [:]
        for entry in keyed {
            if let entry { byKey[entry.key, default: []].append(entry.file) }
        }
        var groups: [DuplicateGroup] = []
        for files in byKey.values where files.count > 1 {
            groups.append(DuplicateGroup(sizeBytes: files[0].sizeBytes,
                                         files: files.sorted { $0.modified > $1.modified }))
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
