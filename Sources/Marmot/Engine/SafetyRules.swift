import Foundation

/// Safety-first boundaries. A path must pass `isSafeToRemove` before the
/// executor will touch it, no matter what a scanner produced.
enum SafetyRules {

    static let home = FileManager.default.homeDirectoryForCurrentUser.path

    /// Absolute prefixes that must never be removed, under any circumstances.
    static var systemProtectedPrefixes: [String] {
        [
            "/System", "/usr", "/bin", "/sbin", "/etc", "/opt", "/Library/Apple",
            "/private/var/db", "/Applications/Utilities",
            home + "/Library/Keychains",
            home + "/Library/Mail", home + "/Library/Messages",
            home + "/Library/Photos", home + "/Library/Mobile Documents",
            home + "/Library/Application Support/MobileSync", // device backups
            home + "/Library/Developer/Xcode/Archives" // signed app archives
        ]
    }

    /// User-content areas protected by default. Only the Duplicates module
    /// may remove explicitly chosen files here (allowUserFiles), and even
    /// then only via trash-first actions.
    static var userDataPrefixes: [String] {
        [
            home + "/Documents", home + "/Desktop", home + "/Pictures",
            home + "/Movies", home + "/Music"
        ]
    }

    static var protectedPrefixes: [String] { systemProtectedPrefixes + userDataPrefixes }

    /// Media library packages must never be reached into, even in
    /// allowUserFiles mode — removing internals corrupts the library.
    static let libraryPackageMarkers = [
        ".photoslibrary", ".musiclibrary", ".aplibrary", ".tvlibrary",
        ".imovielibrary", ".fcpbundle", ".migratedphotolibrary"
    ]

    /// Roots we are allowed to delete *inside* (never the root itself).
    static var allowedRoots: [String] {
        [
            home + "/Library/Caches",
            home + "/Library/Logs",
            home + "/Library/Application Support",
            home + "/Library/Containers",
            home + "/Library/Group Containers",
            home + "/Library/Preferences",
            home + "/Library/Saved Application State",
            home + "/Library/WebKit",
            home + "/Library/HTTPStorages",
            home + "/Library/Cookies",
            home + "/Library/LaunchAgents",
            home + "/Library/Developer",
            home + "/Library/pnpm",
            home + "/.Trash",
            home + "/.npm",
            home + "/.yarn",
            home + "/.cargo",
            home + "/.gradle",
            home + "/Downloads",
            "/Applications",
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons",
            "/Library/Caches",
            "/private/var/folders",
            "/Library/Logs"
        ]
    }

    /// Extra roots allowed only for the project-artifact purge feature.
    static var purgeRoots: [String] {
        let defaults = ["/Projects", "/GitHub", "/dev", "/Code", "/Developer", "/Documents/GitHub", "/repos"]
            .map { home + $0 }
        let custom = UserDefaults.standard.stringArray(forKey: Prefs.purgePaths) ?? []
        return defaults + custom
    }

    /// User-managed whitelist: paths the user never wants touched.
    static var whitelist: [String] {
        get { UserDefaults.standard.stringArray(forKey: Prefs.whitelist) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: Prefs.whitelist) }
    }

    static func isWhitelisted(_ path: String) -> Bool {
        let p = normalize(path)
        return whitelist.contains { p == normalize($0) || p.hasPrefix(normalize($0) + "/") }
    }

    /// The core gate. Conservative: on any doubt, refuse.
    /// `allowUserFiles` is used only by the Duplicates module, where the user
    /// hand-picks individual files inside their own content folders.
    static func isSafeToRemove(_ path: String,
                               allowPurgeRoots: Bool = false,
                               allowUserFiles: Bool = false) -> Bool {
        let p = normalize(path)

        // Basic sanity. NUL bytes are rejected outright: a path truncated at
        // an embedded NUL by a C API could name a different file than the one
        // that was previewed and validated.
        guard p.hasPrefix("/"), !p.contains(".."), p.count > 1,
              !p.contains("\0") else { return false }
        // Never the home dir or a bare volume/top-level path. Depth 2 must
        // stay legal — every app bundle is "/Applications/Name.app" — so the
        // real shallow-path defense is the allowlist below (a depth-2 path
        // only survives if it sits strictly inside an allowed root).
        let components = p.split(separator: "/")
        guard components.count >= 2 else { return false }
        guard p != home else { return false }

        // Never inside a media library package.
        let lower = p.lowercased()
        if libraryPackageMarkers.contains(where: { lower.contains($0) }) { return false }

        // Never anything under an always-protected prefix.
        for prefix in systemProtectedPrefixes {
            let n = normalize(prefix)
            if p == n || p.hasPrefix(n + "/") { return false }
        }
        // User-content areas are protected unless explicitly unlocked.
        if !allowUserFiles {
            for prefix in userDataPrefixes {
                let n = normalize(prefix)
                if p == n || p.hasPrefix(n + "/") { return false }
            }
        }

        // Must be strictly inside (not equal to) an allowed root.
        var roots = allowedRoots
        if allowPurgeRoots { roots += purgeRoots }
        if allowUserFiles { roots += userDataPrefixes }
        let inside = roots.contains { root in
            let r = normalize(root)
            return p.hasPrefix(r + "/") && p.count > r.count + 1
        }
        guard inside else { return false }

        return true
    }

    static func normalize(_ path: String) -> String {
        var p = (path as NSString).expandingTildeInPath
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }
}
