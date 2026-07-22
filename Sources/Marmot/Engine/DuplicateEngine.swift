import Foundation
import CryptoKit
import Darwin

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

    /// Progress phases surfaced to the UI: a live tally while cataloguing,
    /// then a determinate count while hashing.
    enum ScanPhase {
        case collecting(files: Int)
        case comparing(done: Int, total: Int)
    }

    var isCancelled = false
    var onProgress: ((String) -> Void)?
    var onPhase: ((ScanPhase) -> Void)?
    private var candidateFiles = 0

    func scan(roots: [String]) -> [DuplicateGroup] {
        // Size → (path, device:inode). The file ID lets us skip hardlinked
        // twins: removing one hardlink to the same file frees no space.
        var bySize: [Int64: [(path: String, fileID: String)]] = [:]

        candidateFiles = 0
        for root in roots {
            if isCancelled { return [] }
            collectCandidates(root: root, into: &bySize)
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
        onPhase?(.comparing(done: 0, total: candidates.count))

        let hashed = LockedCounter()
        var keyed = [(key: String, file: DuplicateFile)?](repeating: nil, count: candidates.count)
        keyed.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: candidates.count) { index in
                if isCancelled { return }
                let candidate = candidates[index]
                onProgress?(candidate.path)
                let done = hashed.increment()
                if done % 16 == 0 || done == candidates.count {
                    onPhase?(.comparing(done: done, total: candidates.count))
                }
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

    /// One walk per root: stat data (size, device, inode) comes free, and
    /// packages/cloud folders are pruned without ever entering them.
    private func collectCandidates(root: String,
                                   into bySize: inout [Int64: [(path: String, fileID: String)]]) {
        FTSWalker.walk(
            root: root,
            isCancelled: { self.isCancelled },
            directoryPre: { path, _, _ in
                let ext = ((path as NSString).lastPathComponent as NSString)
                    .pathExtension.lowercased()
                if Self.skipExtensions.contains(ext)
                    || DiskScanner.cloudRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
                    return .skip
                }
                return .descend
            },
            file: { path, _, st in
                let size = Int64(st.pointee.st_size)
                guard size >= Self.minFileSize else { return }
                bySize[size, default: []].append(
                    (path: path, fileID: "\(st.pointee.st_dev):\(st.pointee.st_ino)"))
                self.candidateFiles += 1
                if self.candidateFiles % 128 == 0 {
                    self.onPhase?(.collecting(files: self.candidateFiles))
                }
            })
    }

    /// Picks the copy most worth keeping: organized locations beat the
    /// Downloads dumping ground, clean names beat "report copy (2)", the
    /// newest copy breaks ties — and the user's past overrides tilt it.
    static func preferredKeeper(among files: [DuplicateFile]) -> DuplicateFile? {
        let learned = KeeperMemory.weights
        return files.max { keeperScore($0, learned: learned) == keeperScore($1, learned: learned)
            ? $0.modified < $1.modified
            : keeperScore($0, learned: learned) < keeperScore($1, learned: learned) }
    }

    static func keeperScore(_ file: DuplicateFile, learned: [String: Int] = [:]) -> Int {
        var score = learned[KeeperMemory.bucket(for: file.path)] ?? 0
        let home = SafetyRules.home.lowercased()
        let dir = file.directory.lowercased()
        if dir.hasPrefix(home + "/documents") { score += 40 }
        else if dir.hasPrefix(home + "/desktop") { score += 25 }
        else if dir.hasPrefix(home + "/downloads") { score -= 20 }

        let name = file.name.lowercased()
        if name.contains(" copy") || name.contains("duplicate") { score -= 30 }
        if name.range(of: #"\(\d+\)"#, options: .regularExpression) != nil { score -= 30 }

        // Slight preference for organized (deeper) folders over root dumps.
        score += min(file.path.components(separatedBy: "/").count, 10)
        return score
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

/// Learned folder preferences: when the user overrides the suggested keeper,
/// remember which top-level folder won and which lost, and lean that way
/// next time. Small clamped integer weights — learning never overwhelms the
/// built-in heuristics, it only tilts ties and near-ties.
enum KeeperMemory {

    /// The first path component under the user's home ("Documents",
    /// "Downloads", …), or "other".
    static func bucket(for path: String) -> String {
        let home = SafetyRules.home
        guard path.hasPrefix(home + "/") else { return "other" }
        let rest = path.dropFirst(home.count + 1)
        return rest.split(separator: "/").first.map(String.init) ?? "other"
    }

    static var weights: [String: Int] {
        (UserDefaults.standard.dictionary(forKey: Prefs.keeperWeights) as? [String: Int]) ?? [:]
    }

    static func recordOverride(chosen: String, over rejected: String) {
        let chosenBucket = bucket(for: chosen)
        let rejectedBucket = bucket(for: rejected)
        guard chosenBucket != rejectedBucket else { return }
        var updated = weights
        updated[chosenBucket, default: 0] += 5
        updated[rejectedBucket, default: 0] -= 5
        for (key, value) in updated {
            updated[key] = max(-25, min(25, value))
        }
        UserDefaults.standard.set(updated, forKey: Prefs.keeperWeights)
    }
}

/// Thread-safe counter for progress reporting from concurrentPerform.
/// A locked class avoids mutating a captured var from concurrent code.
private final class LockedCounter {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
