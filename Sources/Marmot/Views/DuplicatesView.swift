import SwiftUI
import AppKit

/// Duplicate file finder: identical-content files grouped visually.
/// Pick which copy to keep in each group; the rest go through the usual
/// change preview (trash-first, dry-runnable).
struct DuplicatesView: View {

    @State private var groups: [DuplicateGroup] = []
    @State private var keepers: [UUID: UUID] = [:]     // group id → file id to keep
    @State private var includedGroups: Set<UUID> = []
    @State private var scanning = false
    @State private var scannedOnce = false
    @State private var progressPath = ""
    @State private var phase: DuplicateEngine.ScanPhase?
    @State private var roots: [String] = [
        NSHomeDirectory() + "/Downloads",
        NSHomeDirectory() + "/Documents",
        NSHomeDirectory() + "/Desktop"
    ]
    @State private var activePlan: ChangePlan?
    @State private var engine: DuplicateEngine?

    var totalWasted: Int64 {
        groups.filter { includedGroups.contains($0.id) }.reduce(0) { $0 + $1.wastedBytes }
    }

    var body: some View {
        Group {
            if scanning {
                scanningState
            } else if !scannedOnce {
                startState
            } else if groups.isEmpty {
                EmptyState(icon: "doc.on.doc",
                           title: "No duplicates found",
                           message: "No identical files over 1 MB in the scanned folders. Nice and tidy! ✨")
            } else {
                groupList
            }
        }
        .toolbar { toolbarContent }
        .sheet(item: $activePlan) { plan in
            PlanPreviewView(plan: plan, allowUserFiles: true) { result in
                activePlan = nil
                if let r = result, !r.dryRun { startScan() }
            }
        }
        .navigationSubtitle(scannedOnce && !groups.isEmpty
            ? "\(groups.count) duplicate groups — \(ByteFormat.string(totalWasted)) reclaimable"
            : "")
    }

    // MARK: States

    private var startState: some View {
        StartScreen(icon: "doc.on.doc",
                    title: "Duplicate Finder",
                    message: "Finds files with identical content (verified by hash, not just name) "
                        + "in Downloads, Documents, and Desktop. You choose which copy to keep — "
                        + "removals are trash-first and previewed like everything else.",
                    buttonLabel: "Scan for Duplicates",
                    tint: Theme.color(for: .duplicates),
                    action: { startScan() },
                    extra: {
                        VStack(spacing: 4) {
                            ForEach(roots, id: \.self) { root in
                                Text(root)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    })
    }

    private var scanningState: some View {
        VStack(spacing: 12) {
            switch phase {
            case .comparing(let done, let total):
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .frame(width: 320)
                Text("Comparing \(done) of \(total) candidates…")
                    .font(.callout.monospacedDigit())
            case .collecting(let files):
                ProgressView()
                Text("Cataloguing files… \(files) candidates so far")
                    .font(.callout.monospacedDigit())
            case nil:
                ProgressView()
                Text("Cataloguing files…").font(.callout)
            }
            Text(progressPath)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 480)
            Button("Cancel") { engine?.isCancelled = true }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Group list

    private var groupList: some View {
        List {
            ForEach(groups) { group in
                Section {
                    groupHeader(group)
                    if includedGroups.contains(group.id) {
                        ForEach(group.files) { file in
                            fileRow(file: file, group: group)
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func groupHeader(_ group: DuplicateGroup) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { includedGroups.contains(group.id) },
                set: { on in
                    if on {
                        includedGroups.insert(group.id)
                    } else {
                        includedGroups.remove(group.id)
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Image(systemName: "doc.on.doc")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(group.files.count)× \(group.files.first?.name ?? "")")
                    .font(.headline)
                    .lineLimit(1).truncationMode(.middle)
                Text("\(ByteFormat.string(group.sizeBytes)) each — \(ByteFormat.string(group.wastedBytes)) reclaimable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    /// User's explicit choice wins; otherwise the smart-keeper heuristics.
    private func keeperID(for group: DuplicateGroup) -> UUID? {
        keepers[group.id] ?? DuplicateEngine.preferredKeeper(among: group.files)?.id
    }

    private func fileRow(file: DuplicateFile, group: DuplicateGroup) -> some View {
        let keeperID = keeperID(for: group)
        let isKeeper = file.id == keeperID
        return HStack(spacing: 10) {
            Button {
                keepers[group.id] = file.id
            } label: {
                Image(systemName: isKeeper ? "star.fill" : "star")
                    .foregroundStyle(isKeeper ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .help("Keep this copy")

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(file.name)
                        .font(.callout)
                        .lineLimit(1).truncationMode(.middle)
                    if isKeeper {
                        Badge(text: "KEEP", color: .green)
                    }
                }
                Text(file.directory)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(file.modified.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Reveal") {
                NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: "")
            }
            .controlSize(.small)
        }
        .padding(.leading, 24)
        .opacity(isKeeper ? 1 : 0.8)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                addFolder()
            } label: {
                Label("Add Folder", systemImage: "folder.badge.plus")
            }
            .disabled(scanning)
            Button {
                startScan()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(scanning)
            Button {
                buildPlan()
            } label: {
                Label("Review & Remove…", systemImage: "eye")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(scanning || totalWasted == 0)
            .help("Preview the removal of all non-keeper copies. Trash-first and dry-runnable.")
        }
    }

    // MARK: Actions

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url, !roots.contains(url.path) {
            roots.append(url.path)
            if scannedOnce { startScan() }
        }
    }

    private func startScan() {
        scanning = true
        scannedOnce = true
        groups = []
        keepers = [:]
        includedGroups = []
        phase = nil
        let e = DuplicateEngine()
        engine = e
        e.onProgress = { path in
            DispatchQueue.main.async { progressPath = path }
        }
        e.onPhase = { p in
            DispatchQueue.main.async { phase = p }
        }
        let scanRoots = roots.filter { FileManager.default.fileExists(atPath: $0) }
        Task { @MainActor in
            let found = await Task.detached(priority: .userInitiated) { e.scan(roots: scanRoots) }.value
            if e.isCancelled {
                // Cancelled: return to the start screen, not a misleading
                // "no duplicates found" empty state.
                scannedOnce = false
            } else {
                groups = found
                includedGroups = Set(found.map(\.id))
            }
            phase = nil
            progressPath = ""
            scanning = false
        }
    }

    private func buildPlan() {
        var items: [ChangeItem] = []
        for group in groups where includedGroups.contains(group.id) {
            let keeperID = keeperID(for: group)
            guard let keeper = group.files.first(where: { $0.id == keeperID }) else { continue }
            for file in group.files where file.id != keeper.id {
                items.append(ChangeItem(
                    target: file.path,
                    action: .moveToTrash,
                    sizeBytes: file.sizeBytes,
                    risk: .medium,
                    note: "Identical content to the kept copy at \(keeper.directory).",
                    group: file.directory))
            }
        }
        guard !items.isEmpty else { return }
        activePlan = ChangePlan(title: "Remove Duplicate Files", source: "Duplicates", items: items)
    }
}
