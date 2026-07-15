import SwiftUI
import AppKit

/// Interactive disk map: treemap of folder sizes, click to descend,
/// large-file list, trash-first removal with plan preview.
struct DiskMapView: View {

    @State private var rootNode: FileNode?
    @State private var currentNode: FileNode?
    @State private var largeFiles: [LargeFile] = []
    @State private var scanning = false
    @State private var progressPath = ""
    @State private var scanTarget = NSHomeDirectory()
    @State private var activePlan: ChangePlan?
    @State private var showLargeFiles = false
    @State private var scanner: DiskScanner?
    @State private var hoveredNode: FileNode?
    @State private var folderMovers: FolderTrends.Movers?

    var body: some View {
        VStack(spacing: 0) {
            if scanning {
                scanningState
            } else if let node = currentNode {
                breadcrumb(node)
                Divider()
                if let movers = folderMovers, node.id == rootNode?.id {
                    moversStrip(movers)
                    Divider()
                }
                if showLargeFiles {
                    largeFileList
                } else {
                    TreemapView(node: node,
                                onDescend: { currentNode = $0 },
                                onDelete: { proposeDelete($0) },
                                onHoverNode: { hoveredNode = $0 })
                    Divider()
                    hoverBar
                }
            } else {
                startState
            }
        }
        .toolbar { toolbarContent }
        .sheet(item: $activePlan) { plan in
            PlanPreviewView(plan: plan, allowPurgeRoots: true) { result in
                activePlan = nil
                if let r = result, !r.dryRun { startScan() }
            }
        }
        .navigationSubtitle(currentNode.map { "\($0.path) — \(ByteFormat.string($0.sizeBytes))" } ?? "")
    }

    // MARK: States

    private var startState: some View {
        StartScreen(icon: "square.grid.3x3.topleft.filled",
                    title: "Disk Map",
                    message: "Visualizes where your disk space goes as an interactive treemap. Click a block to zoom in, right-click to reveal or remove. Removal always goes through the change preview.",
                    buttonLabel: "Scan Home Folder",
                    tint: .cyan,
                    action: { scanTarget = NSHomeDirectory(); startScan() },
                    extra: {
                        Button {
                            pickFolder()
                        } label: {
                            Label("Choose Folder…", systemImage: "folder")
                        }
                        .controlSize(.large)
                    })
    }

    private var scanningState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Measuring \(scanTarget)…")
                .font(.callout)
            Text(progressPath)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 480)
            Button("Cancel") {
                scanner?.isCancelled = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func breadcrumb(_ node: FileNode) -> some View {
        HStack(spacing: 4) {
            ForEach(ancestry(of: node), id: \.id) { ancestor in
                Button {
                    currentNode = ancestor
                } label: {
                    Text(ancestor.name)
                        .font(.callout.weight(ancestor.id == node.id ? .semibold : .regular))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ancestor.id == node.id ? .primary : Color.accentColor)
                if ancestor.id != node.id {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text(ByteFormat.string(node.sizeBytes))
                .font(.callout.weight(.semibold).monospacedDigit())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// "What grew" since the previous scan of this root.
    private func moversStrip(_ movers: FolderTrends.Movers) -> some View {
        HStack(spacing: 14) {
            Text("Since \(movers.since.formatted(date: .abbreviated, time: .omitted)):")
                .font(.caption)
                .foregroundStyle(.tertiary)
            ForEach(movers.changes, id: \.name) { change in
                HStack(spacing: 3) {
                    Image(systemName: change.delta > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2)
                        .foregroundStyle(change.delta > 0 ? .pink : .green)
                    Text("\(change.name) \(change.delta > 0 ? "+" : "−")\(ByteFormat.string(abs(change.delta)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    /// Bottom info bar showing whatever block the mouse is over.
    private var hoverBar: some View {
        HStack(spacing: 8) {
            if let node = hoveredNode {
                Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text(node.path)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(ByteFormat.string(node.sizeBytes))
                    .font(.caption.weight(.semibold).monospacedDigit())
            } else {
                Text("Hover a block for details — click to zoom, right-click for actions")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func ancestry(of node: FileNode) -> [FileNode] {
        var chain: [FileNode] = [node]
        var cursor = node
        while let parent = cursor.parent {
            chain.insert(parent, at: 0)
            cursor = parent
        }
        return chain
    }

    private var largeFileList: some View {
        List(largeFiles) { file in
            HStack {
                Image(systemName: "doc")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(file.name).font(.callout)
                    Text(file.path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Text(ByteFormat.string(file.sizeBytes))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Reveal") {
                    NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: "")
                }
                Button("Remove…") {
                    proposeDeletePath(file.path, size: file.sizeBytes)
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            if rootNode != nil {
                Picker("View", selection: $showLargeFiles) {
                    Label("Treemap", systemImage: "square.grid.3x3.topleft.filled").tag(false)
                    Label("Large Files", systemImage: "doc.badge.ellipsis").tag(true)
                }
                .pickerStyle(.segmented)
            }
            Button {
                pickFolder()
            } label: {
                Label("Choose Folder", systemImage: "folder")
            }
            .disabled(scanning)
            Button {
                startScan()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(scanning)
        }
    }

    // MARK: Actions

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: scanTarget)
        if panel.runModal() == .OK, let url = panel.url {
            scanTarget = url.path
            startScan()
        }
    }

    private func startScan() {
        scanning = true
        rootNode = nil
        currentNode = nil
        let target = scanTarget
        let s = DiskScanner()
        scanner = s
        s.onProgress = { path in
            DispatchQueue.main.async { progressPath = path }
        }
        Task { @MainActor in
            let tree = await Task.detached(priority: .userInitiated) { s.scan(root: target) }.value
            rootNode = tree
            currentNode = tree
            largeFiles = s.largeFiles
            scanning = false
            FolderTrends.shared.record(root: target, children: tree.children)
            folderMovers = FolderTrends.shared.movers(root: target)
        }
    }

    private func proposeDelete(_ node: FileNode) {
        proposeDeletePath(node.path, size: node.sizeBytes)
    }

    private func proposeDeletePath(_ path: String, size: Int64) {
        let safe = SafetyRules.isSafeToRemove(path, allowPurgeRoots: true)
        activePlan = ChangePlan(
            title: "Remove \((path as NSString).lastPathComponent)",
            source: "Disk Map",
            items: [ChangeItem(
                target: path,
                action: .moveToTrash,
                sizeBytes: size,
                risk: safe ? .medium : .high,
                note: safe
                    ? "Moves to Trash — recoverable until you empty it."
                    : "This path is outside Marmot's safe-removal zones and will be skipped by the safety gate. Remove it manually in Finder if you are sure.",
                group: "Disk Map")])
    }
}

// (TreemapView lives in TreemapView.swift)
