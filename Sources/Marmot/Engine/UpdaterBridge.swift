import Foundation
import Sparkle

/// Thin wrapper around Sparkle's updater. Updates are verified with the
/// project's EdDSA key (SUPublicEDKey in Info.plist) — independent of Apple
/// code signing, so it works for this ad-hoc-signed open-source app.
final class UpdaterBridge {

    static let shared = UpdaterBridge()

    private var controller: SPUStandardUpdaterController?

    var isActive: Bool { controller != nil }

    /// Called once at launch (from the app delegate, on the main thread).
    /// Skips silently when not running from a bundle, or when the public
    /// key hasn't been configured yet.
    func start() {
        guard Bundle.main.bundlePath.hasSuffix(".app"),
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !key.isEmpty, !key.hasPrefix("PASTE_") else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
