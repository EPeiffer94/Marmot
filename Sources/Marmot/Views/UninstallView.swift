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
    @AppStorage(Prefs.timeCapsule) private var timeCapsule = false

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
                LoadingState(text: "Finding installed apps…")
            } else {
                appTable
            }
        }
        .searchable(text: $search, prompt: "Search apps")
        .toolbar {
            ToolbarItemGroup {
                if buildingPlan { ProgressView().controlSize(.small) }
                Toggle(isOn: $timeCapsule) {
                    Label("Time Capsule", systemImage: "archivebox")
                }
                .help("Before uninstalling, archive the app and its data to a zip you choose — making the uninstall fully reversible, forever.")
                Button {
                    inventory.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                Button {
                    buildPlan(reset: true)
                } label: {
                    Label("Reset…", systemImage: "arrow.counterclockwise")
                }
                .disabled(selectedApp == nil || buildingPlan)
                .help("Clears the app's caches, preferences, and data — a factory reset. The app itself stays installed.")
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
        .onReceive(NotificationCenter.default.publisher(for: .marmotUninstallIntent)) { note in
            guard let path = note.userInfo?["appPath"] as? String else { return }
            if let app = inventory.apps.first(where: { $0.id == path }) {
                search = ""
                selectedApp = app
                buildPlan(reset: (note.userInfo?["reset"] as? Bool) ?? false)
            } else {
                // Inventory may still be loading (e.g. Dock drop at launch) —
                // surface the app by name so it's one click away.
                search = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            }
        }
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
            Button("Reset (keep app, clear its data)…") {
                selectedApp = inventory.apps.first { ids.contains($0.id) }
                buildPlan(reset: true)
            }
            Button("Show in Finder") {
                if let app = inventory.apps.first(where: { ids.contains($0.id) }) {
                    NSWorkspace.shared.selectFile(app.path, inFileViewerRootedAtPath: "")
                }
            }
        }
    }

    private func buildPlan(reset: Bool = false) {
        guard let app = selectedApp else { return }
        buildingPlan = true
        Task { @MainActor in
            var plan = await Task.detached(priority: .userInitiated) {
                reset ? UninstallEngine.resetPlan(for: app)
                      : UninstallEngine.uninstallPlan(for: app)
            }.value

            var prefix: [ChangeItem] = []
            if app.isRunning {
                prefix.append(UninstallEngine.quitItem(for: app))
            }
            // Time Capsule: archive the app and its data first, so the
            // uninstall stays reversible even after the Trash empties.
            if !reset && timeCapsule, let destination = askForArchiveDestination(app: app) {
                let paths = [app.path] + plan.items
                    .filter { $0.action == .moveToTrash && $0.target != app.path }
                    .map(\.target)
                let quoted = paths.map { Shell.quoted($0) }.joined(separator: " ")
                prefix.append(ChangeItem(
                    target: "/usr/bin/zip -qry \(Shell.quoted(destination.path)) \(quoted)",
                    action: .runCommand,
                    note: "Archives the app and all its data to \(destination.lastPathComponent) before anything is removed.",
                    group: "Time Capsule"))
            }
            if !prefix.isEmpty {
                plan = ChangePlan(title: plan.title, source: plan.source, items: prefix + plan.items)
            }
            buildingPlan = false
            activePlan = plan
        }
    }

    private func askForArchiveDestination(app: InstalledApp) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save Time Capsule"
        panel.nameFieldStringValue = "\(app.name)-TimeCapsule.zip"
        panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return panel.runModal() == .OK ? panel.url : nil
    }
}
