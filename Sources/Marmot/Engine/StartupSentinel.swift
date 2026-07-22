import Foundation

/// Startup Sentinel: watches the launch agent/daemon folders and notifies
/// when something NEW starts launching at boot — the day it appears, not
/// months later. Purely observational: removal always goes through the
/// normal Startup Items preview flow.
///
/// First run baselines silently (your existing items are presumed wanted);
/// after that, any unseen plist triggers one notification. Items that
/// disappear are pruned, so a reinstall alerts again.
final class StartupSentinel {

    static let shared = StartupSentinel()
    private var timer: Timer?

    private static let watchedDirs = [
        SafetyRules.home + "/Library/LaunchAgents",
        "/Library/LaunchAgents",
        "/Library/LaunchDaemons"
    ]

    func start() {
        guard enabled else { return }
        check()
        // A boot-time installer is caught on next launch; a mid-session
        // installer within a few hours. Cheap either way (two dir listings).
        timer = Timer.scheduledTimer(withTimeInterval: 4 * 3600, repeats: true) { _ in
            StartupSentinel.shared.check()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    var enabled: Bool {
        UserDefaults.standard.object(forKey: Prefs.sentinelEnabled) as? Bool ?? true
    }

    func check() {
        guard enabled else { return }
        DispatchQueue.global(qos: .utility).async {
            let current = Self.currentPlists()
            let known = UserDefaults.standard.stringArray(forKey: Prefs.sentinelKnown)

            guard let known else {
                // First run: baseline silently.
                UserDefaults.standard.set(Array(current.keys), forKey: Prefs.sentinelKnown)
                return
            }

            let fresh = Self.newArrivals(current: Array(current.keys), known: known)
            if !fresh.isEmpty {
                // Suspicious arrivals get a sharper, specific notification.
                let flagged: [(label: String, flags: [String])] = fresh.compactMap { path in
                    guard let info = current[path] else { return nil }
                    let flags = Self.suspicionFlags(plistPath: path, label: info.label,
                                                    programPath: info.program)
                    return flags.isEmpty ? nil : (info.label, flags)
                }
                if let worst = flagged.first {
                    Notifier.post(
                        title: "⚠️ Suspicious new startup item: \(worst.label)",
                        body: "It \(worst.flags.joined(separator: ", and ")). "
                            + "Review it in Marmot → Startup Items before trusting it.",
                        identifier: "marmot.sentinel")
                } else {
                    let names = fresh.compactMap { current[$0]?.label }.sorted()
                    let listed = names.prefix(3).joined(separator: ", ")
                    let more = names.count > 3 ? " and \(names.count - 3) more" : ""
                    Notifier.post(
                        title: names.count == 1
                            ? "New startup item: \(names[0])"
                            : "\(names.count) new startup items appeared",
                        body: "\(listed)\(more) will now launch automatically. "
                            + "Review it in Marmot → Startup Items.",
                        identifier: "marmot.sentinel")
                }
            }
            UserDefaults.standard.set(Array(current.keys), forKey: Prefs.sentinelKnown)
        }
    }

    /// Pure diff — separated for testability.
    static func newArrivals(current: [String], known: [String]) -> [String] {
        let knownSet = Set(known)
        return current.filter { !knownSet.contains($0) }
    }

    // MARK: Suspicion heuristics

    /// Deterministic red flags for a launchd plist. No AI, no guessing —
    /// each flag is a plain, explainable trait that legitimate software
    /// rarely has. Purely advisory: Marmot never acts on these alone.
    static func suspicionFlags(plistPath: String, label: String, programPath: String) -> [String] {
        var flags: [String] = []

        // Apple impersonation: Apple's own items never live in the user's
        // LaunchAgents folder.
        let labelLower = label.lowercased()
        if plistPath.hasPrefix(SafetyRules.home + "/Library/LaunchAgents/"),
           labelLower.hasPrefix("com.apple.") || labelLower.hasPrefix("com.apple-") {
            flags.append("pretends to be Apple software")
        }

        if !programPath.isEmpty {
            // Executables in temp folders don't survive reboots honestly.
            if programPath.hasPrefix("/tmp/") || programPath.hasPrefix("/var/tmp/")
                || programPath.hasPrefix("/private/tmp/") {
                flags.append("runs a program from a temporary folder")
            }
            // Hidden directories in the program path.
            let components = programPath.split(separator: "/")
            if components.dropLast().contains(where: { $0.hasPrefix(".") }) {
                flags.append("runs a program hidden in a dot-folder")
            }
            // The program it points at doesn't exist.
            if !FileManager.default.fileExists(atPath: programPath) {
                flags.append("points at a program that doesn't exist")
            }
        }
        return flags
    }

    struct PlistInfo {
        let label: String
        let program: String
    }

    /// path → label + program for every third-party launchd plist.
    private static func currentPlists() -> [String: PlistInfo] {
        var result: [String: PlistInfo] = [:]
        for dir in watchedDirs {
            for path in CleanupScanner.children(of: dir) where path.hasSuffix(".plist") {
                let fileName = (path as NSString).lastPathComponent
                // Apple's own items churn with OS updates — not our business
                // in system dirs (the user's own LaunchAgents dir is watched
                // fully, since malware loves to hide there with an
                // official-sounding name).
                if dir != watchedDirs[0] && fileName.lowercased().hasPrefix("com.apple.") { continue }
                var label = (fileName as NSString).deletingPathExtension
                var program = ""
                if let data = FileManager.default.contents(atPath: path),
                   let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
                        as? [String: Any] {
                    label = (plist["Label"] as? String) ?? label
                    program = (plist["Program"] as? String)
                        ?? (plist["ProgramArguments"] as? [String])?.first
                        ?? ""
                }
                result[path] = PlistInfo(label: label, program: program)
            }
        }
        return result
    }
}
