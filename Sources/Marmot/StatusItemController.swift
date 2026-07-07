import AppKit
import SwiftUI
import Combine

/// Menu bar HUD driven directly by AppKit (NSStatusItem + NSPopover).
///
/// We intentionally do NOT use SwiftUI's MenuBarExtra scene: on some macOS
/// builds it enters an endless main-menu rebuild loop (scenesDidChange →
/// makeMainMenu → requestUpdate → …) that pegs the main thread. A plain
/// status item sidesteps that machinery entirely.
final class StatusItemController: NSObject {

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

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
                self?.statusItem?.button?.title = " \(cpu)%"
            }
            .store(in: &cancellables)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private var hudEnabled: Bool {
        UserDefaults.standard.object(forKey: "marmot.hudEnabled") as? Bool ?? true
    }

    @objc private func defaultsChanged() {
        DispatchQueue.main.async { [weak self] in self?.syncVisibility() }
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
