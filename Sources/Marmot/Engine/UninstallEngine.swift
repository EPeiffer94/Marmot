import Foundation
import AppKit
import CoreServices

struct InstalledApp: Identifiable, Hashable {
    let id: String          // bundle path
    let name: String
    let bundleID: String
    let version: String
    let path: String
    let sizeBytes: Int64
    let lastUsed: Date?
    let icon: NSImage?

    var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier?.lowercased() == bundleID.lowercased()
        }
    }

    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Copy with a computed size (sizes are filled in lazily after listing).
    func withSize(_ size: Int64) -> InstalledApp {
        InstalledApp(id: id, name: name, bundleID: bundleID, version: version,
                     path: path, sizeBytes: size, lastUsed: lastUsed, icon: icon)
    }
}

/// Finds installed apps and every remnant an uninstall should take with it:
/// containers, caches, preferences, logs, launch agents, and more.
enum UninstallEngine {

    static let fm = FileManager.default
    static var home: String { SafetyRules.home }

    // MARK: - Inventory

    /// Lists installed apps. With `computeSizes: false` this returns fast
    /// (no recursive size walk); callers can fill sizes in later via
    /// `FileSizer.size(of:)` + `withSize(_:)`.
    static func installedApps(computeSizes: Bool = false) -> [InstalledApp] {
        var apps: [InstalledApp] = []
        var dirs = ["/Applications", home + "/Applications"]
        // One level of vendor subfolders.
        for dir in dirs {
            for sub in CleanupScanner.children(of: dir)
            where !sub.hasSuffix(".app") {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: sub, isDirectory: &isDir), isDir.boolValue {
                    dirs.append(sub)
                }
            }
        }
        for dir in dirs {
            for path in CleanupScanner.children(of: dir) where path.hasSuffix(".app") {
                guard let bundle = Bundle(path: path),
                      let bundleID = bundle.bundleIdentifier else { continue }
                let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                    ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                    ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension
                let version = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
                let lastUsed = lastUsedDate(for: path)
                apps.append(InstalledApp(
                    id: path,
                    name: name,
                    bundleID: bundleID,
                    version: version,
                    path: path,
                    sizeBytes: computeSizes ? FileSizer.size(of: path) : 0,
                    lastUsed: lastUsed,
                    icon: NSWorkspace.shared.icon(forFile: path)
                ))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// True "last opened" via Spotlight metadata, falling back to the
    /// filesystem access date (which backup tools often touch).
    static func lastUsedDate(for path: String) -> Date? {
        if let item = MDItemCreate(kCFAllocatorDefault, path as CFString),
           let date = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date {
            return date
        }
        return (try? URL(fileURLWithPath: path)
            .resourceValues(forKeys: [.contentAccessDateKey]))?.contentAccessDate
    }

    // MARK: - Remnant discovery

    /// Builds the full uninstall plan for an app: bundle + everything it left
    /// around the system, each entry explained.
    static func uninstallPlan(for app: InstalledApp) -> ChangePlan {
        let bundleSize = app.sizeBytes > 0 ? app.sizeBytes : FileSizer.size(of: app.path)
        var items: [ChangeItem] = [
            ChangeItem(target: app.path, action: .moveToTrash, sizeBytes: bundleSize,
                       risk: .low, note: "The application bundle itself.",
                       group: "Application")
        ]
        items += remnants(bundleID: app.bundleID, appName: app.name)
        return ChangePlan(title: "Uninstall \(app.name)", source: "Uninstall", items: items)
    }

    /// Remnants for an app that may or may not still be installed.
    static func remnants(bundleID: String, appName: String) -> [ChangeItem] {
        let id = bundleID
        let idLower = id.lowercased()
        var items: [ChangeItem] = []

        let fileLocations: [(String, String, String)] = [
            (home + "/Library/Application Support", "Application Support", "Settings and data stored by the app."),
            (home + "/Library/Caches", "Caches", "Cache files."),
            (home + "/Library/Containers", "Containers", "Sandboxed app data."),
            (home + "/Library/Group Containers", "Group Containers", "Shared app-group data."),
            (home + "/Library/Logs", "Logs", "Log files."),
            (home + "/Library/Saved Application State", "Saved State", "Window restore state."),
            (home + "/Library/WebKit", "WebKit Data", "Embedded web content data."),
            (home + "/Library/HTTPStorages", "HTTP Storage", "Network/cookie storage."),
            (home + "/Library/Cookies", "Cookies", "Cookie files."),
            (home + "/Library/Preferences", "Preferences", "App preferences.")
        ]

        func matches(_ name: String) -> Bool {
            let n = name.lowercased()
            let base = n.hasSuffix(".plist") ? String(n.dropLast(6)) : n
            if base == idLower || base.hasPrefix(idLower + ".") { return true }
            // Group containers are often "<team>.<bundleid>".
            if base.hasSuffix("." + idLower) { return true }
            // Exact app-name folder in Application Support (e.g. "Slack").
            if base == appName.lowercased() { return true }
            return false
        }

        for (dir, group, why) in fileLocations {
            for path in CleanupScanner.children(of: dir) {
                let name = (path as NSString).lastPathComponent
                guard matches(name) else { continue }
                let nameOnly = name.lowercased() == appName.lowercased()
                let size = FileSizer.size(of: path)
                items.append(ChangeItem(
                    target: path, action: .moveToTrash, sizeBytes: size,
                    risk: nameOnly && group == "Application Support" ? .medium : .low,
                    note: why + (nameOnly ? " Matched by app name — verify it belongs to this app." : ""),
                    group: group))
            }
        }

        // Launch agents & daemons (user and system domains).
        let agentDirs = [
            (home + "/Library/LaunchAgents", "Launch Agents", ChangeAction.moveToTrash),
            ("/Library/LaunchAgents", "Launch Agents (system)", ChangeAction.runAdminCommand),
            ("/Library/LaunchDaemons", "Launch Daemons (system)", ChangeAction.runAdminCommand)
        ]
        for (dir, group, action) in agentDirs {
            for path in CleanupScanner.children(of: dir) {
                let name = ((path as NSString).lastPathComponent).lowercased()
                guard name.hasPrefix(idLower) || name.contains(idLower) else { continue }
                if action == .runAdminCommand {
                    items.append(ChangeItem(
                        target: "launchctl bootout system \"\(path)\" 2>/dev/null; rm -f \"\(path)\"",
                        action: .runAdminCommand,
                        sizeBytes: FileSizer.size(of: path),
                        risk: .medium,
                        note: "Unloads and removes the system launch item \((path as NSString).lastPathComponent).",
                        group: group))
                } else {
                    items.append(ChangeItem(
                        target: path, action: .moveToTrash,
                        sizeBytes: FileSizer.size(of: path), risk: .low,
                        note: "Login/launch item installed by the app.", group: group))
                }
            }
        }

        return items.sorted { ($0.group, $1.sizeBytes) < ($1.group, $0.sizeBytes) }
    }
}
