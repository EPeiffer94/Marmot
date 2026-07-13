import Foundation
import AppKit

struct CleanupCategory: Identifiable {
    let id: String
    let name: String
    let icon: String
    let explanation: String
    var items: [ChangeItem] = []
    var isScanning = false
    var size: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
}

/// Scans the well-known junk locations and produces ChangeItems.
/// Never deletes anything itself. Categories declare *what* to look at as
/// Specs; `buildItems` sizes them in parallel and materializes the results.
enum CleanupScanner {

    static let fm = FileManager.default
    static var home: String { SafetyRules.home }

    /// A removal candidate before sizing.
    struct Spec {
        let path: String
        let group: String
        var risk: RiskLevel = .low
        var note: String = ""
        var action: ChangeAction = .moveToTrash
        var selected: Bool = true
    }

    static func categories() -> [CleanupCategory] {
        [
            CleanupCategory(id: "usercache", name: "User App Caches", icon: "archivebox",
                            explanation: "Per-app caches in ~/Library/Caches. Apps rebuild these automatically."),
            CleanupCategory(id: "logs", name: "Logs & Diagnostics", icon: "doc.text",
                            explanation: "Application logs, crash reports, and diagnostic files."),
            CleanupCategory(id: "browser", name: "Browser Caches", icon: "globe",
                            explanation: "Cache data for Safari, Chrome, Firefox, Edge, Arc, and Brave. Does not touch history, cookies, or passwords."),
            CleanupCategory(id: "dev", name: "Developer Junk", icon: "hammer",
                            explanation: "Xcode DerivedData, simulator caches, and package-manager caches (npm, yarn, pnpm, CocoaPods, Gradle, pip, cargo, Homebrew)."),
            CleanupCategory(id: "appcache", name: "App-Specific Caches", icon: "app.badge",
                            explanation: "Large caches kept by Spotify, Slack, Teams, Discord, Dropbox, and similar apps."),
            CleanupCategory(id: "orphans", name: "Orphaned App Data", icon: "questionmark.folder",
                            explanation: "Support files, caches, and preferences left behind by apps that are no longer installed. Reviewed conservatively — anything ambiguous is left unselected."),
            CleanupCategory(id: "installers", name: "Installer Files", icon: "shippingbox",
                            explanation: "Disk images and package installers in Downloads and Homebrew caches."),
            CleanupCategory(id: "artifacts", name: "Project Build Artifacts", icon: "folder.badge.gearshape",
                            explanation: "node_modules, target, .build, dist, and venv folders in your project directories. Projects touched in the last 7 days are left unselected."),
            CleanupCategory(id: "trash", name: "Trash", icon: "trash",
                            explanation: "Contents of your Trash. Emptying is permanent.")
        ]
    }

    static func scan(categoryID: String) -> [ChangeItem] {
        switch categoryID {
        case "usercache": return scanUserCaches()
        case "logs": return scanLogs()
        case "browser": return scanBrowserCaches()
        case "dev": return scanDeveloper()
        case "appcache": return scanAppCaches()
        case "orphans": return scanOrphans()
        case "installers": return scanInstallers()
        case "artifacts": return scanArtifacts()
        case "trash": return scanTrash()
        default: return []
        }
    }

    // MARK: - Helpers

    static func children(of dir: String) -> [String] {
        (try? fm.contentsOfDirectory(atPath: dir))?.map { dir + "/" + $0 } ?? []
    }

    /// Sizes specs in parallel; keeps the ones that exist and meet the
    /// threshold, largest first.
    static func buildItems(_ specs: [Spec], minSize: Int64) -> [ChangeItem] {
        guard !specs.isEmpty else { return [] }
        var results = [ChangeItem?](repeating: nil, count: specs.count)
        results.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: specs.count) { index in
                let spec = specs[index]
                guard fm.fileExists(atPath: spec.path) else { return }
                let size = FileSizer.size(of: spec.path)
                guard size >= minSize else { return }
                buffer[index] = ChangeItem(target: spec.path, action: spec.action,
                                           sizeBytes: size, risk: spec.risk,
                                           note: spec.note, group: spec.group,
                                           isSelected: spec.selected)
            }
        }
        return results.compactMap { $0 }.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    // MARK: - Categories

    static func scanUserCaches() -> [ChangeItem] {
        let skip: Set<String> = ["com.apple.aned", "com.apple.FaceTime", "CloudKit", "FamilyCircle"]
        let specs = children(of: home + "/Library/Caches").compactMap { path -> Spec? in
            let name = (path as NSString).lastPathComponent
            guard !skip.contains(name) else { return nil }
            return Spec(path: path, group: "User Caches",
                        risk: name.hasPrefix("com.apple.") ? .medium : .low,
                        note: "Cache for \(name). Rebuilt automatically on next launch.")
        }
        return buildItems(specs, minSize: 1024)
    }

    static func scanLogs() -> [ChangeItem] {
        let specs = children(of: home + "/Library/Logs").map { path in
            Spec(path: path, group: "User Logs",
                 note: "Log data for \((path as NSString).lastPathComponent).")
        }
        return buildItems(specs, minSize: 1024)
    }

    static func scanBrowserCaches() -> [ChangeItem] {
        let entries: [(String, String)] = [
            (home + "/Library/Caches/Google/Chrome", "Chrome"),
            (home + "/Library/Caches/com.apple.Safari", "Safari"),
            (home + "/Library/Caches/Firefox", "Firefox"),
            (home + "/Library/Caches/com.microsoft.edgemac", "Edge"),
            (home + "/Library/Caches/company.thebrowser.Browser", "Arc"),
            (home + "/Library/Caches/BraveSoftware", "Brave"),
            (home + "/Library/Application Support/Google/Chrome/Default/Service Worker/CacheStorage", "Chrome Service Workers")
        ]
        let specs = entries.map { path, browser in
            Spec(path: path, group: "Browser Caches",
                 note: "\(browser) cache. History, bookmarks, cookies, and passwords are not affected.")
        }
        return buildItems(specs, minSize: 1024)
    }

    static func scanDeveloper() -> [ChangeItem] {
        let entries: [(String, String, RiskLevel, Bool)] = [
            (home + "/Library/Developer/Xcode/DerivedData", "Xcode DerivedData — rebuilt on next build.", .low, true),
            (home + "/Library/Developer/CoreSimulator/Caches", "Simulator caches.", .low, true),
            (home + "/Library/Developer/Xcode/iOS DeviceSupport", "Debug symbols for old iOS versions. Re-downloaded when a device connects.", .medium, false),
            (home + "/Library/Caches/com.apple.dt.Xcode", "Xcode download cache.", .low, true),
            (home + "/.npm/_cacache", "npm cache.", .low, true),
            (home + "/.yarn/cache", "Yarn cache.", .low, true),
            (home + "/Library/pnpm/store", "pnpm content-addressable store.", .low, true),
            (home + "/Library/Caches/CocoaPods", "CocoaPods cache.", .low, true),
            (home + "/.gradle/caches", "Gradle build cache.", .low, true),
            (home + "/Library/Caches/pip", "pip download cache.", .low, true),
            (home + "/.cargo/registry/cache", "Cargo crate cache.", .low, true),
            (home + "/Library/Caches/Homebrew", "Homebrew downloads. `brew` re-fetches as needed.", .low, true),
            (home + "/Library/Caches/go-build", "Go build cache.", .low, true)
        ]
        let specs = entries.map { path, note, risk, selected in
            Spec(path: path, group: "Developer", risk: risk, note: note, selected: selected)
        }
        return buildItems(specs, minSize: 1024 * 1024)
    }

    static func scanAppCaches() -> [ChangeItem] {
        let entries: [(String, String)] = [
            (home + "/Library/Application Support/Spotify/PersistentCache", "Spotify streaming cache."),
            (home + "/Library/Application Support/Slack/Cache", "Slack cache."),
            (home + "/Library/Application Support/Slack/Service Worker/CacheStorage", "Slack service-worker cache."),
            (home + "/Library/Application Support/discord/Cache", "Discord cache."),
            (home + "/Library/Application Support/Microsoft/Teams/Cache", "Microsoft Teams cache."),
            (home + "/Library/Containers/com.microsoft.teams2/Data/Library/Caches", "Teams (new) cache."),
            (home + "/Library/Application Support/Code/Cache", "VS Code cache."),
            (home + "/Library/Application Support/Code/CachedData", "VS Code cached data."),
            (home + "/Library/Application Support/zoom.us/AutoUpdater", "Zoom old installers."),
            (home + "/Library/Application Support/Dropbox/Cache", "Dropbox cache.")
        ]
        let specs = entries.map { Spec(path: $0.0, group: "App Caches", note: $0.1) }
        return buildItems(specs, minSize: 1024 * 1024)
    }

    /// Conservative orphan detection: reverse-DNS folders/plists whose bundle
    /// ID is not installed and not Apple's.
    /// Precompiled once; the pattern is a constant so failure is impossible
    /// in practice, but we degrade gracefully instead of force-trying.
    static let bundleIDRegex = try? NSRegularExpression(
        pattern: "^[A-Za-z0-9-]+\\.[A-Za-z0-9-]+\\.[A-Za-z0-9-.]+$")

    static func scanOrphans() -> [ChangeItem] {
        let installed = installedBundleIDs()
        guard let bundleIDPattern = bundleIDRegex else { return [] }

        func looksLikeBundleID(_ name: String) -> Bool {
            let base = name.hasSuffix(".plist") ? String(name.dropLast(6)) : name
            let range = NSRange(base.startIndex..., in: base)
            return bundleIDPattern.firstMatch(in: base, range: range) != nil
        }
        func owner(of name: String) -> String {
            let base = name.hasSuffix(".plist") ? String(name.dropLast(6)) : name
            return base.lowercased()
        }
        func isOrphan(_ name: String) -> Bool {
            let id = owner(of: name)
            guard looksLikeBundleID(name) else { return false }
            guard !id.hasPrefix("com.apple.") && !id.hasPrefix("group.com.apple.") else { return false }
            return !installed.contains { id == $0 || id.hasPrefix($0 + ".") || $0.hasPrefix(id + ".") }
        }

        let locations: [(String, String, RiskLevel)] = [
            (home + "/Library/Caches", "Orphaned Caches", .low),
            (home + "/Library/Application Support", "Orphaned App Support", .medium),
            (home + "/Library/Preferences", "Orphaned Preferences", .medium),
            (home + "/Library/Saved Application State", "Orphaned Saved State", .low),
            (home + "/Library/HTTPStorages", "Orphaned HTTP Storage", .low),
            (home + "/Library/WebKit", "Orphaned WebKit Data", .low)
        ]
        var specs: [Spec] = []
        for (dir, group, risk) in locations {
            for path in children(of: dir) {
                let name = (path as NSString).lastPathComponent
                guard isOrphan(name) else { continue }
                specs.append(Spec(path: path, group: group, risk: risk,
                                  note: "\(owner(of: name)) does not appear to be installed anymore.",
                                  selected: risk == .low))
            }
        }
        return buildItems(specs, minSize: 4096)
    }

    static func installedBundleIDs() -> Set<String> {
        var ids = Set<String>()
        let dirs = ["/Applications", "/System/Applications",
                    "/System/Applications/Utilities", home + "/Applications",
                    "/Applications/Utilities"]
        for dir in dirs {
            for app in children(of: dir) where app.hasSuffix(".app") {
                if let bundle = Bundle(path: app), let id = bundle.bundleIdentifier {
                    ids.insert(id.lowercased())
                }
            }
            // One level of subfolders (e.g. /Applications/Adobe X/).
            for sub in children(of: dir) where !sub.hasSuffix(".app") {
                for app in children(of: sub) where app.hasSuffix(".app") {
                    if let bundle = Bundle(path: app), let id = bundle.bundleIdentifier {
                        ids.insert(id.lowercased())
                    }
                }
            }
        }
        // Running apps count as installed no matter where they live.
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier { ids.insert(id.lowercased()) }
        }
        return ids
    }

    static func scanInstallers() -> [ChangeItem] {
        let exts: Set<String> = ["dmg", "pkg", "iso", "xip", "mpkg"]
        var specs: [Spec] = []
        for dir in [home + "/Downloads", home + "/Library/Caches/Homebrew/downloads"] {
            for path in children(of: dir)
            where exts.contains((path as NSString).pathExtension.lowercased()) {
                specs.append(Spec(path: path,
                                  group: dir.contains("Homebrew") ? "Homebrew" : "Downloads",
                                  note: "Installer file. Safe to remove after the app is installed."))
            }
        }
        return buildItems(specs, minSize: 1024 * 1024)
    }

    static func scanArtifacts() -> [ChangeItem] {
        let artifactNames: Set<String> = ["node_modules", "target", ".build", "dist", "build", "venv", ".venv", "Pods", ".next", ".nuxt"]
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        var specs: [Spec] = []

        for root in SafetyRules.purgeRoots where fm.fileExists(atPath: root) {
            for project in children(of: root) {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: project, isDirectory: &isDir), isDir.boolValue else { continue }
                let recent = (FileSizer.modificationDate(project) ?? .distantPast) > cutoff
                let projectName = (project as NSString).lastPathComponent
                for artifact in children(of: project)
                where artifactNames.contains((artifact as NSString).lastPathComponent) {
                    let name = (artifact as NSString).lastPathComponent
                    specs.append(Spec(path: artifact, group: "Build Artifacts",
                                      risk: recent ? .medium : .low,
                                      note: "\(name) in \(projectName)\(recent ? " — project modified within 7 days" : "").",
                                      selected: !recent))
                }
            }
        }
        return buildItems(specs, minSize: 10 * 1024 * 1024)
    }

    static func scanTrash() -> [ChangeItem] {
        let specs = children(of: home + "/.Trash").map {
            Spec(path: $0, group: "Trash",
                 note: "Already in Trash. Removing is permanent.",
                 action: .deletePermanently)
        }
        return buildItems(specs, minSize: 1)
    }
}
