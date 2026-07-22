import SwiftUI
import AppKit

/// Duplicate file finder: identical-content files grouped visually.
/// Pick which copy to keep in each group; the rest go through the usual
/// change preview (trash-first, dry-runnable).
/// Scan state lives in DuplicatesModel so results survive navigation.
struct DuplicatesView: View {

    @ObservedObject private var model = DuplicatesModel.shared
    @State private var activePlan: ChangePlan?

    var body: some View {
        Group {
            if model.scanning {
                scanningState
            } else if !model.scannedOnce {
                startState
            } else if model.groups.isEmpty {
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
                if let r = result, !r.dryRun { model.startScan() }
            }
        }
        .navigationSubtitle(model.scannedOnce && !model.groups.isEmpty
            ? "\(model.groups.count) duplicate groups — \(ByteFormat.string(model.totalWasted)) reclaimable"
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
                    action: { model.startScan() },
                    extra: {
                        VStack(spacing: 4) {
                            ForEach(model.roots, id: \.self) { root in
                                Text(root)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    })
    }

    @ViewBuilder
    private var scanningState: some View {
        switch model.phase {
        case .comparing(let done, let total):
            ScanningStateView(title: "Comparing \(done) of \(total) candidates…",
                              progress: (done: done, total: total),
                              path: model.progressPath) { model.cancel() }
        case .collecting(let files):
            ScanningStateView(title: "Cataloguing files… \(files) candidates so far",
                              path: model.progressPath) { model.cancel() }
        case nil:
            ScanningStateView(title: "Cataloguing files…",
                              path: model.progressPath) { model.cancel() }
        }
    }

    // MARK: Group list

    private var groupList: some View {
        List {
            ForEach(model.groups) { group in
                Section {
                    groupHeader(group)
                    if model.includedGroups.contains(group.id) {
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
                get: { model.includedGroups.contains(group.id) },
                set: { on in
                    if on {
                        model.includedGroups.insert(group.id)
                    } else {
                        model.includedGroups.remove(group.id)
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

    private func fileRow(file: DuplicateFile, group: DuplicateGroup) -> some View {
        let keeperID = model.keeperID(for: group)
        let isKeeper = file.id == keeperID
        return HStack(spacing: 10) {
            Button {
                // Overriding the suggested keeper teaches the heuristics
                // which folders this user actually prefers.
                if let suggested = DuplicateEngine.preferredKeeper(among: group.files),
                   suggested.id != file.id {
                    KeeperMemory.recordOverride(chosen: file.path, over: suggested.path)
                }
                model.keepers[group.id] = file.id
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
            Button("Peek") {
                QuickLook.show(path: file.path)
            }
            .controlSize(.small)
            .help("Quick Look this copy before deciding which to keep")
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
            .disabled(model.scanning)
            Button {
                model.startScan()
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
            .disabled(model.scanning || model.totalWasted == 0)
            .help("Preview the removal of all non-keeper copies. Trash-first and dry-runnable.")
        }
    }

    // MARK: Actions

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url, !model.roots.contains(url.path) {
            model.roots.append(url.path)
            if model.scannedOnce { model.startScan() }
        }
    }

    private func buildPlan() {
        var items: [ChangeItem] = []
        for group in model.groups where model.includedGroups.contains(group.id) {
            let keeperID = model.keeperID(for: group)
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
