import Foundation
import Darwin

/// The one correct fts(3) traversal. Every scanner walks the disk through
/// this: FTS_PHYSICAL (symlinks never followed), FTS_NOCHDIR, FTS_XDEV
/// (volume boundaries never crossed).
///
/// The argv array handed to fts_open must remain valid heap memory for the
/// ENTIRE walk — fts reads it lazily during fts_read, not just at open.
/// That requirement once caused a dangling-pointer bug that made every size
/// report zero; it is now satisfied in exactly one place: here.
enum FTSWalker {

    enum DirectoryAction {
        case descend
        case skip
    }

    /// Walks `root` depth-first.
    /// - `directoryPre` fires on entering a directory (root included,
    ///   level 0); return `.skip` to prune it without descending.
    /// - `directoryPost` fires when a descended directory is complete.
    /// - `file` fires for every regular file with its stat data.
    /// Symlinks, unreadable directories, and stat failures are skipped.
    /// Returns false if the walk couldn't start (unreadable root) so
    /// callers with fallbacks have a signal.
    @discardableResult
    static func walk(
        root: String,
        isCancelled: () -> Bool = { false },
        directoryPre: (String, Int, UnsafeMutablePointer<stat>?) -> DirectoryAction = { _, _, _ in .descend },
        directoryPost: (String, Int) -> Void = { _, _ in },
        file: (String, Int, UnsafeMutablePointer<stat>) -> Void
    ) -> Bool {
        guard let dup = strdup(root) else { return false }
        let argv = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: 2)
        argv[0] = dup
        argv[1] = nil
        defer {
            free(dup)
            argv.deallocate()
        }
        guard let fts = fts_open(argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return false }
        defer { fts_close(fts) }

        while let entry = fts_read(fts) {
            if isCancelled() { break }
            let info = Int32(entry.pointee.fts_info)
            let path = String(cString: entry.pointee.fts_path)
            let level = Int(entry.pointee.fts_level)

            switch info {
            case FTS_D:
                if directoryPre(path, level, entry.pointee.fts_statp) == .skip {
                    _ = fts_set(fts, entry, FTS_SKIP)
                }
            case FTS_DP:
                directoryPost(path, level)
            case FTS_F:
                if let st = entry.pointee.fts_statp {
                    file(path, level, st)
                }
            default:
                continue
            }
        }
        return true
    }
}
