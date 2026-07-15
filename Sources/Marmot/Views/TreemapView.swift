import SwiftUI
import AppKit

/// Squarified treemap rendering for the Disk Map. Layout math lives in
/// TreemapLayout; this view handles color, hover, zoom, and context actions.
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
        case "mp4", "mov", "mkv", "avi", "m4v", "webm": return .blue
        case "jpg", "jpeg", "png", "heic", "gif", "tiff", "raw", "cr2", "arw": return .pink
        case "mp3", "m4a", "wav", "flac", "aac", "aiff": return .mint
        case "zip", "dmg", "pkg", "tar", "gz", "7z", "rar", "iso", "xip": return .teal
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "key", "numbers": return .cyan
        case "swift", "js", "ts", "py", "rb", "go", "rs", "c", "cpp", "h", "java", "json", "xml", "html", "css": return .green
        case "app": return .pink
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
