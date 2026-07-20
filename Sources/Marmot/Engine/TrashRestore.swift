import Foundation

/// Moves a trashed item back to its original location.
/// Shared by the History table's Restore button and the post-clean Undo toast.
enum TrashRestore {

    /// Returns nil on success, or a human-readable reason on failure.
    static func restore(target: String, from: String) -> String? {
        let fm = FileManager.default
        let name = (target as NSString).lastPathComponent
        guard fm.fileExists(atPath: from) else {
            return "\(name) is no longer in the Trash — it may have been emptied."
        }
        guard !fm.fileExists(atPath: target) else {
            return "Something already exists at the original location of \(name)."
        }
        do {
            try fm.createDirectory(atPath: (target as NSString).deletingLastPathComponent,
                                   withIntermediateDirectories: true)
            try fm.moveItem(atPath: from, toPath: target)
            return nil
        } catch {
            return "Restore failed: \(error.localizedDescription)"
        }
    }
}
