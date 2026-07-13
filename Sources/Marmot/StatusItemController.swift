import AppKit
import SwiftUI
import Combine

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

        // Quiet background rescan every 4 hours — only when alerts are on.
        backgroundScanTimer = Timer.scheduledTimer(withTimeInterval: 4 * 3600, repeats: true) { _ in
            Task { @MainActor in
                guard UserDefaults.standard.integer(forKey: Prefs.junkAlertGB) > 0 else { return }
                CleanupModel.shared.rescan()
            }
        }
    }

    private func updateJunkAlert(total: Int64) {
        let thresholdGB = UserDefaults.standard.integer(forKey: Prefs.junkAlertGB)
        junkAlerted = thresholdGB > 0 && total > Int64(thresholdGB) * 1_000_000_000
        refreshTitle()
    }

    private func refreshTitle() {
        statusItem?.button?.title = " \(latestCPU)%" + (junkAlerted ? " ⚠︎" : "")
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
