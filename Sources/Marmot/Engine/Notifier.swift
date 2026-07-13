import Foundation
import UserNotifications

/// One place for posting user notifications, shared by the junk alert and
/// Autopilot. Requests authorization lazily on first use.
enum Notifier {

    static func post(title: String, body: String, identifier: String = UUID().uuidString) {
        // UserNotifications requires a bundled app (crashes under `swift run`).
        guard Bundle.main.bundleIdentifier != nil,
              Bundle.main.bundlePath.hasSuffix(".app") else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: identifier,
                                             content: content, trigger: nil))
        }
    }
}
