import AppKit
import SwiftUI
import Combine
import UserNotifications

/// Menu bar HUD driven directly by AppKit (NSStatusItem + NSPopover).
///
/// We intentionally do NOT use SwiftUI's MenuBarExtra scene: on some macOS
/// builds it enters an endless main-menu rebuild loop (scenesDidChange →
/// makeMainMenu → requestUpdate → …) that pegs the main thread. A plain
/// status item sidesteps that machinery entirely.
@MainActor
final class StatusItemController: NSObject {

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    private var latestCPU = 0
    private var junkAlerted = false
    private var backgroundScanTimer: Timer?

    override init() {
        super.init()

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarHUD().environmentObject(StatsSampler.shared))

        syncVisibility()

        // React to the Settings toggle (marmot.hudEnabled).
        NotificationCenter.default.addObserver(
            self, selector: #selector(defaultsChanged),
            name: UserDefaults.didChangeNotification, object: nil)

        // Update the label only when the displayed integer actually changes.
        StatsSampler.shared.$snapshot
            .map { Int($0.cpu.totalUsage) }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cpu in
                Task { @MainActor [weak self] in
                    self?.latestCPU = cpu
                    self?.refreshTitle()
                }
            }
            .store(in: &cancellables)

        // Health alert: notify (debounced) when the score drops below the
        // user's threshold.
        StatsSampler.shared.$snapshot
            .map(\.healthScore)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] score in
                Task { @MainActor [weak self] in
                    self?.maybeAlertHealth(score: score)
                }
            }
            .store(in: &cancellables)

        // Junk alert: watch the cleanup model's total against the threshold.
        CleanupModel.shared.$categories
            .map { $0.reduce(Int64(0)) { $0 + $1.size } }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] total in
                Task { @MainActor [weak self] in
                    self?.updateJunkAlert(total: total)
                }
            }
            .store(in: &cancellables)

        // Quiet background rescan every 4 hours — only when alerts are on,
        // and never when a scan already ran within the last hour (Autopilot
        // and manual scans count).
        backgroundScanTimer = Timer.scheduledTimer(withTimeInterval: 4 * 3600, repeats: true) { _ in
            Task { @MainActor in
                guard UserDefaults.standard.integer(forKey: Prefs.junkAlertGB) > 0 else { return }
                if let last = CleanupModel.shared.lastScan,
                   Date().timeIntervalSince(last) < 3600 { return }
                CleanupModel.shared.rescan()
            }
        }
    }

    private func updateJunkAlert(total: Int64) {
        let thresholdGB = UserDefaults.standard.integer(forKey: Prefs.junkAlertGB)
        let wasAlerted = junkAlerted
        junkAlerted = thresholdGB > 0 && total > Int64(thresholdGB) * 1_000_000_000
        refreshTitle()
        if junkAlerted && !wasAlerted {
            maybeNotify(total: total)
        }
    }

    /// Health-drop notification: fires when the score sits below the user's
    /// threshold, at most once per 6 hours, naming the worst factor.
    private func maybeAlertHealth(score: Int) {
        let threshold = UserDefaults.standard.integer(forKey: Prefs.healthAlertBelow)
        guard threshold > 0, score < threshold else { return }
        let last = UserDefaults.standard.double(forKey: Prefs.healthAlertNotifiedAt)
        let now = Date().timeIntervalSince1970
        guard now - last > 6 * 3600 else { return }
        UserDefaults.standard.set(now, forKey: Prefs.healthAlertNotifiedAt)

        let worst = StatsSampler.shared.snapshot.healthReport.worst
        let cause = worst.map { "\($0.name): \($0.reading). " } ?? ""
        Notifier.post(title: "System health dropped to \(score)",
                      body: cause + "Open Marmot → Live Status for the full breakdown.",
                      identifier: "marmot.healthAlert")
    }

    /// Posts a real notification on the rising edge, at most once per day.
    private func maybeNotify(total: Int64) {
        let last = UserDefaults.standard.double(forKey: Prefs.junkAlertNotifiedAt)
        let now = Date().timeIntervalSince1970
        guard now - last > 24 * 3600 else { return }
        UserDefaults.standard.set(now, forKey: Prefs.junkAlertNotifiedAt)

        Notifier.post(title: "Marmot found reclaimable junk",
                      body: "\(ByteFormat.string(total)) can be reviewed and cleaned. Nothing is removed without your approval.",
                      identifier: "marmot.junkAlert")
    }

    private func refreshTitle() {
        // Figure-space pad (U+2007, digit-width) so 9% and 42% occupy the same
        // width — the menu bar item no longer jumps when digits change.
        let padded = latestCPU < 10 ? "\u{2007}\(latestCPU)" : "\(latestCPU)"
        statusItem?.button?.title = " \(padded)%" + (junkAlerted ? " ⚠︎" : "")
    }

    private var hudEnabled: Bool {
        UserDefaults.standard.object(forKey: Prefs.hudEnabled) as? Bool ?? true
    }

    /// UserDefaults notifications can arrive on any thread; hop to the actor.
    @objc nonisolated private func defaultsChanged() {
        Task { @MainActor [weak self] in
            self?.syncVisibility()
        }
    }

    private func syncVisibility() {
        if hudEnabled && statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                button.image = NSImage(systemSymbolName: "gauge.with.needle",
                                       accessibilityDescription: "Marmot")
                button.imagePosition = .imageLeading
                button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
                button.title = " –%"
                button.target = self
                button.action = #selector(togglePopover(_:))
            }
            statusItem = item
        } else if !hudEnabled, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
