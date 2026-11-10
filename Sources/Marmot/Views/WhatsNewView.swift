import SwiftUI

/// In-app release highlights, shown once after each update lands via
/// Sparkle. Maintainers: refresh `WhatsNew.highlights` during the release
/// ritual — the version comparison handles the rest.
enum WhatsNew {

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    static let highlights: [(icon: String, text: String)] = [
        ("doc.on.doc",
         "Duplicates now works in folders you add, like an external drive, and checks each copy byte for byte against the one you keep."),
        ("folder.badge.gearshape",
         "Build folders in ~/Documents/GitHub are cleaned instead of skipped, and .iso files in Downloads are no longer selected for you."),
        ("arrow.down.circle",
         "App Updates finds more Sparkle updates and stops reporting ones that aren't real."),
        ("checkmark.shield",
         "Uninstalls stop if the app won't quit or the Time Capsule backup fails, and quitting the app no longer asks you where it is.")
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
