import SwiftUI

/// App update overview across Homebrew, Sparkle, and the Mac App Store.
struct UpdatesView: View {

    @State private var updates: [AppUpdate] = []
    @State private var checking = false
    @State private var checkedOnce = false
    @State private var upgrading: Set<String> = []
    @State private var message: String?

    var body: some View {
        Group {
            if checking && updates.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Checking Homebrew, Sparkle feeds, and the App Store…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !checkedOnce {
                startState
            } else if updates.isEmpty {
                EmptyState(icon: "checkmark.seal",
                           title: "Everything is up to date",
                           message: "No outdated apps found via Homebrew, Sparkle feeds, or the App Store.")
            } else {
                updateList
            }
        }
        .toolbar {
            ToolbarItemGroup {
                if checking { ProgressView().controlSize(.small) }
                Button {
                    check()
                } label: {
                    Label("Check for Updates", systemImage: "arrow.clockwise")
                }
                .disabled(checking)
            }
        }
        .navigationSubtitle(checkedOnce ? "\(updates.count) updates available" : "")
    }

    private var startState: some View {
        VStack(spacing: 16) {
            EmptyState(icon: "arrow.down.app",
                       title: "App Updates",
                       message: "Checks every installed app for newer versions using Homebrew, the app's own Sparkle update feed, and the Mac App Store. Nothing installs without your say-so.")
            Button {
                check()
            } label: {
                Label("Check for Updates", systemImage: "magnifyingglass")
                    .frame(width: 180)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            Spacer().frame(height: 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var updateList: some View {
        List {
            if let message {
                Label(message, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
            ForEach(updates) { update in
                HStack(spacing: 12) {
                    Image(systemName: channelIcon(update.channel))
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(update.appName).font(.headline)
                        Text("\(update.installedVersion)  →  \(update.latestVersion)")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(update.channel)
                        .font(.caption)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                    actionButton(update)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    @ViewBuilder
    private func actionButton(_ update: AppUpdate) -> some View {
        if update.channel == "Homebrew" {
            Button {
                upgrade(update)
            } label: {
                if upgrading.contains(update.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Upgrade")
                }
            }
            .disabled(upgrading.contains(update.id))
            .help(update.howToUpdate)
        } else {
            Text(update.howToUpdate)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 220, alignment: .trailing)
        }
    }

    private func channelIcon(_ channel: String) -> String {
        switch channel {
        case "Homebrew": return "mug"
        case "Sparkle": return "sparkle"
        default: return "bag"
        }
    }

    private func check() {
        checking = true
        checkedOnce = true
        message = nil
        Task.detached(priority: .userInitiated) {
            let apps = UninstallEngine.installedApps()
            let found = await UpdateChecker.checkAll(apps: apps)
            await MainActor.run {
                updates = found
                checking = false
                if Shell.brewPath == nil {
                    message = "Homebrew not found — only Sparkle and App Store channels were checked."
                }
            }
        }
    }

    private func upgrade(_ update: AppUpdate) {
        guard let brew = Shell.brewPath else { return }
        let cask = update.id.replacingOccurrences(of: "brew:", with: "")
        upgrading.insert(update.id)
        Task.detached {
            let out = Shell.run(brew, ["upgrade", "--cask", cask], timeout: 600)
            await MainActor.run {
                upgrading.remove(update.id)
                if out.succeeded {
                    updates.removeAll { $0.id == update.id }
                    message = "Upgraded \(update.appName)."
                } else {
                    message = "Upgrade failed: \(out.stderr.prefix(200))"
                }
            }
        }
    }
}
