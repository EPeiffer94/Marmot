import SwiftUI

/// Disk Time Travel: scrub through a folder's size history and watch the
/// treemap morph. Growth glows pink, shrinkage glows green. Read-only —
/// this is a viewing instrument, not a cleaning tool.
struct TimeTravelView: View {

    let root: String
    let snapshots: [FolderTrends.Snapshot]
    var onClose: () -> Void

    @State private var index: Int
    @State private var playing = false

    private let ticker = Timer.publish(every: 0.9, on: .main, in: .common).autoconnect()

    init(root: String, snapshots: [FolderTrends.Snapshot], onClose: @escaping () -> Void) {
        self.root = root
        self.snapshots = snapshots
        self.onClose = onClose
        _index = State(initialValue: max(snapshots.count - 1, 0))
    }

    private var current: FolderTrends.Snapshot? {
        snapshots.indices.contains(index) ? snapshots[index] : nil
    }

    private var previous: [String: Int64]? {
        index > 0 ? snapshots[index - 1].sizes : nil
    }

    private var totalBytes: Int64 {
        current?.sizes.values.reduce(0, +) ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let snapshot = current {
                DiffTreemap(sizes: snapshot.sizes, previous: previous)
                    .padding(8)
            } else {
                EmptyState(icon: "clock.arrow.circlepath",
                           title: "Not enough history",
                           message: "Scan this folder in the Disk Map on different days to build a timeline.")
            }
            Divider()
            controls
        }
        .frame(width: 780, height: 560)
        .onReceive(ticker) { _ in
            guard playing, snapshots.count > 1 else { return }
            index = index < snapshots.count - 1 ? index + 1 : 0
        }
    }

    private var header: some View {
        HStack {
            Label("Time Travel", systemImage: "clock.arrow.circlepath")
                .font(.title3.weight(.semibold))
            Text((root as NSString).abbreviatingWithTildeInPath)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let snapshot = current {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(snapshot.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.headline)
                    Text(ByteFormat.string(totalBytes))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button {
                playing.toggle()
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
            }
            .disabled(snapshots.count < 2)
            .help(playing ? "Pause" : "Play through history")

            if let first = snapshots.first {
                Text(first.date.formatted(date: .numeric, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Slider(value: Binding(
                get: { Double(index) },
                set: { index = Int($0.rounded()); playing = false }
            ), in: 0...Double(max(snapshots.count - 1, 1)), step: 1)
            if let last = snapshots.last {
                Text(last.date.formatted(date: .numeric, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 4) {
                Circle().fill(.pink).frame(width: 7, height: 7)
                Text("grew").font(.caption2).foregroundStyle(.secondary)
                Circle().fill(.green).frame(width: 7, height: 7)
                Text("shrank").font(.caption2).foregroundStyle(.secondary)
            }

            Button("Done") { onClose() }
                .keyboardShortcut(.defaultAction)
        }
        .padding()
    }
}

/// One-level treemap of a historical snapshot, tinted by change vs the
/// previous snapshot.
private struct DiffTreemap: View {
    let sizes: [String: Int64]
    let previous: [String: Int64]?

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size).insetBy(dx: 2, dy: 2)
            let nodes = sizes
                .map { FileNode(name: $0.key, path: $0.key, isDirectory: true, sizeBytes: $0.value) }
                .sorted { $0.sizeBytes > $1.sizeBytes }
            let cells = TreemapLayout.layout(nodes: nodes, in: rect)
            ZStack(alignment: .topLeading) {
                ForEach(Array(cells.enumerated()), id: \.element.id) { position, cell in
                    cellView(cell, index: position)
                        .frame(width: cell.rect.width, height: cell.rect.height)
                        .offset(x: cell.rect.minX, y: cell.rect.minY)
                }
            }
            .animation(.easeInOut(duration: 0.45), value: sizes)
        }
    }

    private func delta(for name: String) -> Int64 {
        guard let previous else { return 0 }
        return (sizes[name] ?? 0) - (previous[name] ?? 0)
    }

    private func cellView(_ cell: TreemapLayout.Cell, index: Int) -> some View {
        let change = delta(for: cell.node.name)
        let magnitude = min(0.55, Double(abs(change)) / Double(max(cell.node.sizeBytes, 1)))
        return RoundedRectangle(cornerRadius: 3)
            .fill(Palette.color(for: index).opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .fill(change > 0 ? Color.pink.opacity(magnitude)
                        : change < 0 ? Color.green.opacity(magnitude) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
            )
            .overlay(alignment: .topLeading) {
                if cell.rect.width > 64 && cell.rect.height > 30 {
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
            .help(changeHelp(cell.node.name, size: cell.node.sizeBytes, change: change))
    }

    private func changeHelp(_ name: String, size: Int64, change: Int64) -> String {
        var text = "\(name) — \(ByteFormat.string(size))"
        if change > 0 { text += "  (+\(ByteFormat.string(change)) since previous)" }
        if change < 0 { text += "  (−\(ByteFormat.string(abs(change))) since previous)" }
        return text
    }
}
