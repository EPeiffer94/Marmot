import SwiftUI
import AppKit

/// Smart uninstaller: pick an app, see the full removal plan (bundle, caches,
/// preferences, containers, launch agents), dry-run or apply.
struct UninstallView: View {

    @State private var apps: [InstalledApp] = []
    @State private var loading = false
    @State private var search = ""
    @State private var selectedApp: InstalledApp?
    @State private var buildingPlan = false
    @State private var activePlan: ChangePlan?

    var filtered: [InstalledApp] {
        guard !search.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.bundleID.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        Group {
            if loading && apps.isEmpty {
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
                    load()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
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
                if let r = result, !r.dryRun { load() }
            }
        }
        .onAppear { if apps.isEmpty { load() } }
        .navigationSubtitle("\(apps.count) apps installed")
    }

    private var appTable: some View {
        Table(filtered, selection: Binding(
            get: { selectedApp.map { Set([$0.id]) } ?? [] },
            set: { ids in selectedApp = filtered.first { ids.contains($0.id) } }
        )) {
            TableColumn("App") { app in
                HStack(spacing: 8) {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 22, height: 22)
                    }
                    Text(app.name)
                    if app.isRunning {
                        Text("running")
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                }
            }
            .width(min: 220)
            TableColumn("Version") { app in
                Text(app.version).foregroundStyle(.secondary)
            }
            .width(90)
            TableColumn("Size") { app in
                Text(app.sizeBytes > 0 ? ByteFormat.string(app.sizeBytes) : "…")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(90)
            TableColumn("Last Used") { app in
                Text(app.lastUsed.map { $0.formatted(.relative(presentation: .named)) } ?? "—")
                    .foregroundStyle(.secondary)
            }
            .width(120)
            TableColumn("Bundle ID") { app in
                Text(app.bundleID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            Button("Uninstall…") {
                selectedApp = apps.first { ids.contains($0.id) }
                buildPlan()
            }
            Button("Show in Finder") {
                if let app = apps.first(where: { ids.contains($0.id) }) {
                    NSWorkspace.shared.selectFile(app.path, inFileViewerRootedAtPath: "")
                }
            }
        }
    }

    private func load() {
        loading = true
        Task.detached(priority: .userInitiated) {
            // Phase 1: fast listing — show apps immediately, sizes still unknown.
            let found = UninstallEngine.installedApps(computeSizes: false)
            await MainActor.run {
                apps = found
                loading = false
            }
            // Phase 2: fill in sizes in parallel, updating rows as they land.
            await withTaskGroup(of: (String, Int64).self) { group in
                for app in found {
                    group.addTask { (app.id, FileSizer.size(of: app.path)) }
                }
                for await (id, size) in group {
                    await MainActor.run {
                        if let index = apps.firstIndex(where: { $0.id == id }) {
                            apps[index] = apps[index].withSize(size)
                        }
                    }
                }
            }
        }
    }

    private func buildPlan() {
        guard let app = selectedApp else { return }
        buildingPlan = true
        Task.detached(priority: .userInitiated) {
            let plan = UninstallEngine.uninstallPlan(for: app)
            await MainActor.run {
                buildingPlan = false
                if app.isRunning {
                    // Prepend a quit step so files aren't in use.
                    var items = plan.items
                    items.insert(ChangeItem(
                        target: "osascript -e 'tell application \"\(app.name)\" to quit'",
                        action: .runCommand, sizeBytes: 0, risk: .low,
                        note: "Quits \(app.name) before removal.",
                        group: "Before removal"), at: 0)
                    activePlan = ChangePlan(title: plan.title, source: plan.source, items: items)
                } else {
                    activePlan = plan
                }
            }
        }
    }
}
