import Foundation
import AppKit

/// Best-effort permission probes. macOS offers no query API for TCC grants,
/// so we test readability of a file that is only readable with the grant.
enum Permissions {

    /// Full Disk Access: the TCC database itself is unreadable without it.
    static var hasFullDiskAccess: Bool {
        let probe = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
        return FileManager.default.isReadableFile(atPath: probe)
    }

    static func openFullDiskAccessSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    /// True when any plan item points into an app container — the area most
    /// commonly blocked without Full Disk Access.
    static func planTouchesProtectedContainers(_ items: [ChangeItem]) -> Bool {
        items.contains {
            $0.target.contains("/Library/Containers/")
                || $0.target.contains("/Library/Group Containers/")
        }
    }
}
