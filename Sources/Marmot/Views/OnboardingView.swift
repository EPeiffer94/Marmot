import SwiftUI
import AppKit

/// First-run walkthrough: what Marmot is, how preview-first works, and the
/// one permission worth granting (Full Disk Access).
struct OnboardingView: View {

    var onDone: () -> Void
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            footer
        }
        .frame(width: 520, height: 420)
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: pages[page].icon)
                .font(.system(size: 52))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
            Text(pages[page].title)
                .font(.title2.weight(.semibold))
            Text(pages[page].message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            if page == 2 {
                Button {
                    openFullDiskAccessSettings()
                } label: {
                    Label("Open Full Disk Access Settings", systemImage: "lock.open")
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Circle()
                        .fill(index == page ? Color.accentColor : Color.primary.opacity(0.15))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal)
    }

    private var footer: some View {
        HStack {
            Button("Skip") { onDone() }
            Spacer()
            if page > 0 {
                Button("Back") { withAnimation { page -= 1 } }
            }
            if page < pages.count - 1 {
                Button("Continue") { withAnimation { page += 1 } }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Get Started") { onDone() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private struct Page {
        let icon: String
        let title: String
        let message: String
    }

    private let pages: [Page] = [
        Page(icon: "sparkles",
             title: "Welcome to Marmot",
             message: "Clean, uninstall, analyze, maintain, and monitor your Mac — free and open source. Marmot never deletes anything without showing you exactly what will change first."),
        Page(icon: "eye",
             title: "Preview first. Always.",
             message: "Every action produces a Change Plan you can review item by item. Use Dry Run to simulate the whole thing — nothing on disk is touched — and files go to the Trash so they stay recoverable."),
        Page(icon: "lock.shield",
             title: "One permission worth granting",
             message: "Full Disk Access lets Marmot's scanners see protected areas like Mail data and other apps' containers. Without it nothing breaks — those spots are just skipped. Add Marmot to the list, then relaunch.")
    ]

    private func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
