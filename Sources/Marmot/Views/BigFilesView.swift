import SwiftUI
import AppKit

/// "Large & Old" hunter: every file over the threshold anywhere in your home
/// folder, filterable by size and age, sortable, removable trash-first.
/// Scan state lives in BigFilesModel so results survive navigation.
struct BigFilesView: View {

    @ObservedObject private var model = BigFilesModel.shared
    @State private var selection: Set<BigFile.ID> = []
    @State private var sortOrder = [KeyPathComparator(\BigFile.sizeBytes, order: .reverse)]
    @State private var activePlan: ChangePlan?

    private var filtered: [BigFile] {
        let minBytes = Int64(model.minSizeMB) * 1024 * 1024
        let cutoff = model.minAgeDays > 0
            ? Date().addingTimeInterval(-Double(model.minAgeDays) * 86400)
            : Date.distantFuture
        return model.files
            .filter { $0.sizeBytes >= minBytes && $0.modified < cutoff }
            .sorted(using: sortOrder)
    }

    private var selectedFiles: [BigFile] {
        filtered.filter { selection.contains($0.id) }
    }

    private var selectedBytes: Int64 {
        selectedFiles.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        Group {
            if model.scanning {
                scanningState
            } else if !model.scannedOnce {
                startState
            } else if filtered.isEmpty {
                EmptyState(icon: "externaldrive",
                           title: "No files match",
                           message: "Nothing this large (or this old) outside of app bundles and cloud folders. Try lowering the filters.")
            } else {
                fileTable
            }
        }
        .toolbar { toolbarContent }
        .sheet(item: $activePlan) { plan in
            PlanPreviewView(plan: plan, allowPurgeRoots: true, allowUserFiles: true) { result in
                activePlan = nil
                if let r = result, !r.dryRun { startScan() }
            }
        }
        .navigationSubtitle(model.scannedOnce
            ? "\(filtered.count) files — selected \(ByteFormat.string(selectedBytes))"
            : "")
        .onReceive(NotificationCenter.default.publisher(for: .marmotBigFilesIntent)) { note in
            let requestedSize = note.userInfo?["minSizeMB"] as? Int ?? 100
            let requestedAge = note.userInfo?["minAgeDays"] as? Int ?? 0
            model.minSizeMB = [5000, 1000, 500, 100].first { $0 <= max(requestedSize, 100) } ?? 100
            model.minAgeDays = requestedAge >= 365 ? 365 : (requestedAge >= 180 ? 180 : 0)
            if !model.scannedOnce && !model.scanning { startScan() }
        }
    }

    // MARK: States

    private var startState: some View {
        StartScreen(icon: "externaldrive",
                    title: "Big Files",
                    message: "Hunts down every file over 100 MB in your home folder — then filter by size and age to find the huge, forgotten ones. Removal is trash-first with a full preview, like everything in Marmot.",
                    buttonLabel: "Hunt Big Files",
                    tint: Theme.color(for: .bigFiles)) {
            startScan()
        }
    }

    private var scanningState: some View {
        ScanningStateView(
            title: model.foundCount > 0
                ? "Found \(model.foundCount) big files — \(ByteFormat.string(model.foundBytes)) so far"
                : "Hunting big files…",
            path: model.progressPath) { model.cancel() }
    }

    // MARK: Table

    private var fileTable: some View {
        Table(filtered, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { file in
                Text(file.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: 200)
            TableColumn("Where") { file in
                Text(file.directory)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            TableColumn("Size", value: \.sizeBytes) { file in
                Text(ByteFormat.string(file.sizeBytes))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(90)
            TableColumn("Modified", value: \.modified) { file in
                Text(file.modified.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.secondary)
            }
            .width(110)
        }
        .contextMenu(forSelectionType: BigFile.ID.self) { ids in
            Button("Reveal in Finder") {
                if let file = model.files.first(where: { ids.contains($0.id) }) {
                    NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: "")
                }
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Picker("Min size", selection: $model.minSizeMB) {
                Text("100 MB+").tag(100)
                Text("500 MB+").tag(500)
                Text("1 GB+").tag(1000)
                Text("5 GB+").tag(5000)
            }
            Picker("Age", selection: $model.minAgeDays) {
                Text("Any age").tag(0)
                Text("6+ months").tag(180)
                Text("1+ year").tag(365)
            }
            Button {
                startScan()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.scanning)
            Button {
                buildPlan()
            } label: {
                Label("Review & Remove…", systemImage: "eye")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(selection.isEmpty || model.scanning)
        }
    }

    // MARK: Actions

    private func startScan() {
        selection = []
        model.startScan()
    }

    private func buildPlan() {
        let items = selectedFiles.map { file in
            ChangeItem(target: file.path,
                       action: .moveToTrash,
                       sizeBytes: file.sizeBytes,
                       risk: .medium,
                       note: "Last modified \(file.modified.formatted(date: .abbreviated, time: .omitted)).",
                       group: file.directory)
        }
        guard !items.isEmpty else { return }
        activePlan = ChangePlan(title: "Remove Big Files", source: "Big Files", items: items)
    }
}
