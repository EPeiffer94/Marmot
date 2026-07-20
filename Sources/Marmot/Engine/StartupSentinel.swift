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
                let names = fresh.compactMap { current[$0] }.sorted()
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
            UserDefaults.standard.set(Array(current.keys), forKey: Prefs.sentinelKnown)
        }
    }

    /// Pure diff — separated for testability.
    static func newArrivals(current: [String], known: [String]) -> [String] {
        let knownSet = Set(known)
        return current.filter { !knownSet.contains($0) }
    }

    /// path → human label for every third-party launchd plist.
    private static func currentPlists() -> [String: String] {
        var result: [String: String] = [:]
        for dir in watchedDirs {
            for path in CleanupScanner.children(of: dir) where path.hasSuffix(".plist") {
                let fileName = (path as NSString).lastPathComponent
                // Apple's own items churn with OS updates — not our business
                // in system dirs (the user's own LaunchAgents dir is watched
                // fully, since malware loves to hide there with an
                // official-sounding name).
                if dir != watchedDirs[0] && fileName.lowercased().hasPrefix("com.apple.") { continue }
                result[path] = (fileName as NSString).deletingPathExtension
            }
        }
        return result
    }
}
