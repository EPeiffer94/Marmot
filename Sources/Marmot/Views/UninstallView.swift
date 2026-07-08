import SwiftUI
import AppKit

/// Smart uninstaller: pick an app, see the full removal plan (bundle, caches,
/// preferences, containers, launch agents), dry-run or apply.
struct UninstallView: View {

    @ObservedObject private var inventory = AppInventory.shared
    @State private var search = ""
    @State private var selectedApp: InstalledApp?
    @State private var buildingPlan = false
    @State private var activePlan: ChangePlan?
    @State private var sortOrder = [KeyPathComparator(\InstalledApp.name)]

    var filtered: [InstalledApp] {
        var apps = inventory.apps
        if !search.isEmpty {
            apps = apps.filter {
                $0.name.localizedCaseInsensitiveContains(search) ||
                $0.bundleID.localizedCaseInsensitiveContains(search)
            }
        }
        return apps.sorted(using: sortOrder)
    }

    var body: some View {
        Group {
            if inventory.loading && inventory.apps.isEmpty {
                ProgressView("Finding installed apps…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                appTable
            }
        }
        .searchable(text: $search, prompt: "Search apps")
        .toolbar {
            ToolbarItemGroup {
                if buildingPlan { ProgressView().controlSize(.small) }
                Button {
                    inventory.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                Button {
                    buildPlan()
                } label: {
                    Label("Uninstall…", systemImage: "trash")
                }
                .disabled(selectedApp == nil || buildingPlan)
                .help("Shows everything that would be removed — the app plus all leftovers — before anything happens.")
            }
        }
        .sheet(item: $activePlan) { plan in
            PlanPreviewView(plan: plan) { result in
                activePlan = nil
                if let r = result, !r.dryRun { inventory.refresh() }
            }
        }
        .onAppear { inventory.loadIfNeeded() }
        .navigationSubtitle("\(inventory.apps.count) apps installed")
    }

    private var appTable: some View {
        Table(filtered, selection: Binding(
            get: { selectedApp.map { Set([$0.id]) } ?? [] },
            set: { ids in selectedApp = filtered.first { ids.contains($0.id) } }
        ), sortOrder: $sortOrder) {
            TableColumn("App", value: \.name) { app in
                HStack(spacing: 8) {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 22, height: 22)
                    }
                    Text(app.name)
                    if app.isRunning {
                        Badge(text: "running", color: .green)
                    }
                }
            }
            .width(min: 220)
            TableColumn("Version") { app in
                Text(app.version).foregroundStyle(.secondary)
            }
            .width(90)
            TableColumn("Size", value: \.sizeBytes) { app in
                Text(app.sizeBytes > 0 ? ByteFormat.string(app.sizeBytes) : "…")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(90)
            TableColumn("Last Used", value: \.lastUsedOrDistantPast) { app in
                Text(app.lastUsed.map { $0.formatted(.relative(presentation: .named)) } ?? "—")
                    .foregroundStyle(.secondary)
            }
            .width(120)
            TableColumn("Bundle ID", value: \.bundleID) { app in
                Text(app.bundleID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            Button("Uninstall…") {
                selectedApp = inventory.apps.first { ids.contains($0.id) }
                buildPlan()
            }
            Button("Show in Finder") {
                if let app = inventory.apps.first(where: { ids.contains($0.id) }) {
                    NSWorkspace.shared.selectFile(app.path, inFileViewerRootedAtPath: "")
                }
            }
        }
    }

    private func buildPlan() {
        guard let app = selectedApp else { return }
        buildingPlan = true
        Task { @MainActor in
            var plan = await Task.detached(priority: .userInitiated) {
                UninstallEngine.uninstallPlan(for: app)
            }.value
            if app.isRunning {
                let quit = ChangeItem(
                    target: "osascript -e 'tell application \"\(app.name)\" to quit'",
                    action: .runCommand,
                    note: "Quits \(app.name) before removal.",
                    group: "Before removal")
                plan = ChangePlan(title: plan.title, source: plan.source, items: [quit] + plan.items)
            }
            buildingPlan = false
            activePlan = plan
        }
    }
}
