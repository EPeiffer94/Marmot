import SwiftUI

/// The shared "scan in progress" screen used by every scanning tool:
/// headline (spinner, or a determinate bar when totals are known), the path
/// currently being touched, and Cancel.
struct ScanningStateView: View {
    let title: String
    var progress: (done: Int, total: Int)? = nil
    var path: String = ""
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if let progress {
                ProgressView(value: Double(progress.done),
                             total: Double(max(progress.total, 1)))
                    .frame(width: 320)
            } else {
                ProgressView()
            }
            Text(title)
                .font(.callout.monospacedDigit())
                .contentTransition(.numericText())
                .animation(.default, value: title)
            Text(path)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 480)
            Button("Cancel", action: onCancel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Posts a deep-link notification after a short delay so the destination
/// view has time to mount before it receives the intent.
enum DeepLink {
    static func post(_ name: Notification.Name,
                     userInfo: [String: Any] = [:],
                     delay: TimeInterval = 0.15) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)
        }
    }
}
