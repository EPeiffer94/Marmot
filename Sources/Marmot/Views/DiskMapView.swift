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

    var body: some View {
        VStack(spacing: 0) {
            if scanning {
                scanningState
            } else if let node = currentNode {
                breadcrumb(node)
                Divider()
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
                    action: { scanTarget = NSHomeDirectory(); startScan() }) {
            Button {
                pickFolder()
            } label: {
                Label("Choose Folder…", systemImage: "folder")
            }
            .controlSize(.large)
        }
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

// MARK: - Treemap rendering

struct TreemapView: View {
    let node: FileNode
    let onDescend: (FileNode) -> Void
    let onDelete: (FileNode) -> Void
    var onHoverNode: (FileNode?) -> Void = { _ in }

    @State private var hovered: UUID?

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size).insetBy(dx: 4, dy: 4)
            let cells = TreemapLayout.layout(nodes: node.children, in: rect)
            ZStack(alignment: .topLeading) {
                if cells.isEmpty {
                    EmptyState(icon: "tray",
                               title: "Nothing to show",
                               message: "This folder is empty or unreadable.")
                }
                ForEach(cells) { cell in
                    cellView(cell)
                        .frame(width: cell.rect.width, height: cell.rect.height)
                        .offset(x: cell.rect.minX, y: cell.rect.minY)
                }
            }
        }
        .padding(4)
    }

    /// Directories cycle through the palette; files are colored by type so
    /// media, archives, code, and documents are visually distinct.
    private func cellColor(_ cell: TreemapLayout.Cell) -> Color {
        if cell.node.isDirectory {
            let index = node.children.firstIndex { $0.id == cell.node.id } ?? 0
            return Palette.color(for: index)
        }
        switch (cell.node.name as NSString).pathExtension.lowercased() {
        case "mp4", "mov", "mkv", "avi", "m4v", "webm": return .purple
        case "jpg", "jpeg", "png", "heic", "gif", "tiff", "raw", "cr2", "arw": return .pink
        case "mp3", "m4a", "wav", "flac", "aac", "aiff": return .indigo
        case "zip", "dmg", "pkg", "tar", "gz", "7z", "rar", "iso", "xip": return .orange
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "key", "numbers": return .teal
        case "swift", "js", "ts", "py", "rb", "go", "rs", "c", "cpp", "h", "java", "json", "xml", "html", "css": return .blue
        case "app": return .red
        default: return .gray
        }
    }

    @ViewBuilder
    private func cellView(_ cell: TreemapLayout.Cell) -> some View {
        let color = cellColor(cell)
        RoundedRectangle(cornerRadius: 3)
            .fill(color.opacity(hovered == cell.id ? 0.85 : (cell.node.isDirectory ? 0.65 : 0.45)))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color.black.opacity(0.15), lineWidth: 0.5)
            )
            .overlay(alignment: .topLeading) {
                if cell.rect.width > 56 && cell.rect.height > 26 {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(cell.node.name)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                        Text(ByteFormat.string(cell.node.sizeBytes))
                            .font(.system(size: 9).monospacedDigit())
                            .opacity(0.75)
                    }
                    .padding(4)
                    .foregroundStyle(.white)
                }
            }
            .onHover { inside in
                if inside {
                    hovered = cell.id
                    onHoverNode(cell.node)
                } else if hovered == cell.id {
                    hovered = nil
                    onHoverNode(nil)
                }
            }
            .onTapGesture {
                if cell.node.isDirectory && !cell.node.children.isEmpty {
                    onDescend(cell.node)
                }
            }
            .contextMenu {
                Text("\(cell.node.name) — \(ByteFormat.string(cell.node.sizeBytes))")
                Divider()
                if cell.node.isDirectory && !cell.node.children.isEmpty {
                    Button("Open in Map") { onDescend(cell.node) }
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(cell.node.path, inFileViewerRootedAtPath: "")
                }
                Button("Remove…", role: .destructive) { onDelete(cell.node) }
            }
            .help("\(cell.node.path)\n\(ByteFormat.string(cell.node.sizeBytes))")
    }
}
