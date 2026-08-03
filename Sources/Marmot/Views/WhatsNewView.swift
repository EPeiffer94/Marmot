import SwiftUI

/// In-app release highlights, shown once after each update lands via
/// Sparkle. Maintainers: refresh `WhatsNew.highlights` during the release
/// ritual — the version comparison handles the rest.
enum WhatsNew {

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    static let highlights: [(icon: String, text: String)] = [
        ("sparkles",
         "Marmot is rebuilt for macOS 26 — Liquid Glass on the toast, drop target, and ⌘K palette, with the system chrome to match."),
        ("gauge.with.needle",
         "The health score shows its receipt — every factor, its live reading, and the exact points it costs."),
        ("light.beacon.max",
         "Startup Sentinel calls out suspicious new launch items — Apple impersonators, programs in temp or hidden folders."),
        ("bolt",
         "Scan results survive navigation, app sizes appear instantly on relaunch, and duplicate hashing is easier on your disk.")
    ]

    /// True once per updated version, never on a fresh install (onboarding
    /// covers that) and never twice for the same version.
    static func shouldShow() -> Bool {
        guard !version.isEmpty else { return false }
        let seen = UserDefaults.standard.string(forKey: Prefs.lastSeenVersion)
        if seen == version { return false }
        if seen == nil {
            UserDefaults.standard.set(version, forKey: Prefs.lastSeenVersion)
            return false
        }
        return true
    }

    static func markSeen() {
        UserDefaults.standard.set(version, forKey: Prefs.lastSeenVersion)
    }
}

struct WhatsNewView: View {
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("🐿️").font(.system(size: 40))
                Text("What's new in Marmot \(WhatsNew.version)")
                    .font(.title3.weight(.semibold))
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(WhatsNew.highlights, id: \.text) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.icon)
                            .font(.title3)
                            .foregroundStyle(Theme.accent)
                            .frame(width: 28)
                        Text(item.text)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 28)

            Spacer()
            Divider()
            HStack {
                Spacer()
                Button("Nice — let's go") { onClose() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 460, height: 380)
    }
}
