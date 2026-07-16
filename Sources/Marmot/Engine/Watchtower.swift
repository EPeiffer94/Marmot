import Foundation

/// Scheduled update checks for ALL installed apps — daily or weekly — with a
/// notification when anything is outdated. (Standalone apps charge for this.)
final class Watchtower {

    static let shared = Watchtower()

    private var timer: Timer?
    private var running = false

    /// Called once at launch (from the app delegate, on the main thread).
    func start() {
        Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { _ in
            Task { @MainActor in Watchtower.shared.checkIfDue() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { @MainActor in Watchtower.shared.checkIfDue() }
        }
    }

    func checkIfDue() {
        let days = UserDefaults.standard.integer(forKey: Prefs.watchtowerDays)
        guard days > 0, !running else { return }
        let last = UserDefaults.standard.double(forKey: Prefs.watchtowerLastCheck)
        guard Date().timeIntervalSince1970 - last > Double(days) * 86_400 else { return }

        running = true
        Task { @MainActor in
            defer { self.running = false }
            let updates = await Task.detached(priority: .utility) {
                await UpdateChecker.checkAll(apps: UninstallEngine.installedApps())
            }.value
            UserDefaults.standard.set(Date().timeIntervalSince1970,
                                      forKey: Prefs.watchtowerLastCheck)
            guard !updates.isEmpty else { return }

            let names = updates.prefix(3).map(\.appName).joined(separator: ", ")
            let suffix = updates.count > 3 ? ", …" : ""
            Notifier.post(
                title: updates.count == 1
                    ? "1 app update available"
                    : "\(updates.count) app updates available",
                body: "\(names)\(suffix) — open Marmot → App Updates to review.",
                identifier: "marmot.watchtower")
        }
    }
}
