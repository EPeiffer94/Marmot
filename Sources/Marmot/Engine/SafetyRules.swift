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
        return whitelist.contains { isSameOrInside(p, normalize($0)) }
    }

    /// The first whitelisted path that sits strictly *inside* `path`.
    /// Removing `path` would carry that protected item to the Trash with
    /// it, so the executor skips the whole folder and names the culprit.
    static func whitelistedDescendant(of path: String) -> String? {
        let p = normalize(path)
        return whitelist.map(normalize).first { isStrictlyInside($0, p) }
    }

    /// The core gate. Conservative: on any doubt, refuse.
    /// `allowUserFiles` is used only by the Duplicates module, where the user
    /// hand-picks individual files inside their own content folders.
    static func isSafeToRemove(_ path: String,
                               allowPurgeRoots: Bool = false,
                               allowUserFiles: Bool = false,
                               extraRoots: [String] = []) -> Bool {
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
        guard pathKey(p) != pathKey(home) else { return false }

        // Never inside a media library package.
        let lower = pathKey(p)
        if libraryPackageMarkers.contains(where: { lower.contains($0) }) { return false }

        // Never an always-protected area, anything inside one, or a folder
        // that contains one (e.g. ~/Library/Developer/Xcode holds Archives).
        for prefix in systemProtectedPrefixes {
            let n = normalize(prefix)
            if isSameOrInside(p, n) || isStrictlyInside(n, p) { return false }
        }
        // Folders the user explicitly picked for this plan (e.g. Duplicates
        // scan folders), minus anything too broad or system-owned.
        let extras = extraRoots.filter(isAcceptableExtraRoot)

        // User-content areas are protected unless explicitly unlocked — by
        // user-files mode, by a project folder the user registered inside
        // them (e.g. ~/Documents/GitHub), or by a folder picked for this plan.
        if !allowUserFiles
            && !(allowPurgeRoots && isInsideUserDataPurgeRoot(p))
            && !isInside(p, anyOf: extras) {
            for prefix in userDataPrefixes where isSameOrInside(p, normalize(prefix)) {
                return false
            }
        }

        // Must be strictly inside (not equal to) an allowed root.
        var roots = allowedRoots
        if allowPurgeRoots { roots += purgeRoots }
        if allowUserFiles { roots += userDataPrefixes }
        roots += extras
        let matching = roots.map(normalize).filter { isStrictlyInside(p, $0) }
        guard let root = matching.max(by: { $0.count < $1.count }) else { return false }

        // The string checks above only mean something if the path really
        // lives where it says. A symlinked folder between the root and the
        // item would send the removal somewhere else entirely.
        guard !traversesSymlink(p, below: root) else { return false }

        return true
    }

    /// True when `p` sits strictly inside one of `roots`.
    static func isInside(_ p: String, anyOf roots: [String]) -> Bool {
        roots.contains { isStrictlyInside(p, normalize($0)) }
    }

    /// Project folders the user keeps inside a protected content area, such
    /// as ~/Documents/GitHub (GitHub Desktop's default). Only a strict
    /// subfolder counts: a purge root of ~/Documents itself never unlocks the
    /// whole folder.
    static func isInsideUserDataPurgeRoot(_ p: String) -> Bool {
        let unlocked = purgeRoots.map(normalize).filter { root in
            !root.contains("..") && userDataPrefixes.contains { isStrictlyInside(root, normalize($0)) }
        }
        return isInside(p, anyOf: unlocked)
    }

    /// A folder the user explicitly picked (e.g. a Duplicates scan folder)
    /// may act as a removal root for that plan — but never "/", the home
    /// folder, anything in ~/Library, a top-level system folder, or a
    /// system-protected area.
    static func isAcceptableExtraRoot(_ root: String) -> Bool {
        let r = normalize(root)
        guard r.hasPrefix("/"), !r.contains(".."), !r.contains("\0"),
              r.split(separator: "/").count >= 2,
              pathKey(r) != pathKey(home) else { return false }
        let tooBroad = [home + "/Library", "/Library", "/Applications", "/private", "/Users/Shared"]
        for prefix in tooBroad + systemProtectedPrefixes where isSameOrInside(r, normalize(prefix)) {
            return false
        }
        return true
    }

    // MARK: - Path comparison

    /// Comparison key. APFS is case- and normalization-insensitive by
    /// default, so ".../documents" and ".../Documents" are the same folder
    /// and must be treated the same by every rule.
    static func pathKey(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.lowercased()
    }

    /// `p` equals `root` or sits inside it. Both must be normalized.
    static func isSameOrInside(_ p: String, _ root: String) -> Bool {
        let a = pathKey(p), r = pathKey(root)
        return a == r || a.hasPrefix(r + "/")
    }

    /// `p` sits strictly inside `root`. Both must be normalized.
    static func isStrictlyInside(_ p: String, _ root: String) -> Bool {
        let a = pathKey(p), r = pathKey(root)
        return a.hasPrefix(r + "/") && a.count > r.count + 1
    }

    /// True when a folder *between* `root` and the item is a symbolic link.
    /// The item itself may be a link (trashing a link removes only the
    /// link), and the root is trusted. A component that doesn't exist ends
    /// the check: there is nothing on disk to follow.
    static func traversesSymlink(_ p: String, below root: String) -> Bool {
        let parts = p.split(separator: "/").map(String.init)
        let rootDepth = root.split(separator: "/").count
        guard parts.count > rootDepth + 1 else { return false }
        var current = "/" + parts[0..<rootDepth].joined(separator: "/")
        for part in parts[rootDepth..<(parts.count - 1)] {
            current += "/" + part
            var st = stat()
            guard lstat(current, &st) == 0 else { return false }
            if (st.st_mode & S_IFMT) == S_IFLNK { return true }
        }
        return false
    }

    static func normalize(_ path: String) -> String {
        var p = (path as NSString).expandingTildeInPath
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }
}
