import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = StatusItemController()
        Autopilot.shared.start()
        UpdaterBridge.shared.start()
        Watchtower.shared.start()
    }
}

@main
struct MarmotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // Plain reference — NOT @StateObject. The App body must never observe the
    // sampler; scene re-evaluation on every stats tick caused a main-menu
    // rebuild storm. The menu bar HUD is AppKit-driven (StatusItemController).
    private let stats = StatsSampler.shared

    init() {
        StatsSampler.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(stats)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    UpdaterBridge.shared.checkForUpdates()
                }
            }
        }

        Settings {
            SettingsView()
        }
    }
}
