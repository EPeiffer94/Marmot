import SwiftUI

/// Operation history — every applied change and every dry run, from the
/// append-only JSONL log.
struct HistoryView: View {

    @State private var entries: [LogEntry] = []
    @State private var filter: Filter = .all
    @State private var message: String?
    @State private var restoredIDs: Set<UUID> = []

    enum Filter: String, CaseIterable {
        case all = "All"
        case applied = "Applied"
        case dryRuns = "Dry Runs"
    }

    var filtered: [LogEntry] {
        switch filter {
        case .all: return entries
        case .applied: return entries.filter { !$0.dryRun }
        case .dryRuns: return entries.filter { $0.dryRun }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let message {
                Label(message, systemImage: "arrow.uturn.backward.circle")
                    .font(.callout)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4))
            }
            if filtered.isEmpty {
                EmptyState(icon: "clock.arrow.circlepath",
                           title: "No history yet",
                           message: "Every change Marmot applies — and every dry run — is recorded here.")
            } else {
                Table(filtered) {
                    TableColumn("Date") { entry in
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                    .width(150)
                    TableColumn("Source") { entry in
                        HStack(spacing: 5) {
                            Text(entry.source)
                            if entry.dryRun {
                                Badge(text: "dry run", color: .blue)
                            }
                        }
                    }
                    .width(140)
                    TableColumn("Action") { entry in
                        Text(entry.action).foregroundStyle(.secondary)
                    }
                    .width(130)
                    TableColumn("Target") { entry in
                        Text(entry.target)
                            .font(.caption.monospaced())
                            .lineLimit(1).truncationMode(.middle)
                    }
                    TableColumn("Size") { entry in
                        Text(entry.sizeBytes > 0 ? ByteFormat.string(entry.sizeBytes) : "—")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(80)
                    TableColumn("Outcome") { entry in
                        Text(entry.outcome)
                            .foregroundStyle(entry.outcome.hasPrefix("Failed") ? .red : .secondary)
                    }
                    .width(160)
                    TableColumn("") { entry in
                        if isRestorable(entry) {
                            Button("Restore") { restore(entry) }
                                .controlSize(.small)
                                .help("Moves the item from the Trash back to its original location.")
                        }
                    }
                    .width(70)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                Button {
                    entries = OperationLog.shared.readAll()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear { entries = OperationLog.shared.readAll() }
        .navigationSubtitle("\(entries.count) recorded operations")
    }

    // MARK: Restore

    private func isRestorable(_ entry: LogEntry) -> Bool {
        entry.trashedTo != nil
            && !entry.dryRun
            && entry.outcome == ItemOutcome.done.rawValue
            && entry.action == ChangeAction.moveToTrash.rawValue
            && !restoredIDs.contains(entry.id)
    }

    private func restore(_ entry: LogEntry) {
        guard let from = entry.trashedTo else { return }
        let fm = FileManager.default
        let name = (entry.target as NSString).lastPathComponent
        guard fm.fileExists(atPath: from) else {
            message = "\(name) is no longer in the Trash — it may have been emptied."
            return
        }
        guard !fm.fileExists(atPath: entry.target) else {
            message = "Something already exists at the original location of \(name)."
            return
        }
        do {
            try fm.createDirectory(atPath: (entry.target as NSString).deletingLastPathComponent,
                                   withIntermediateDirectories: true)
            try fm.moveItem(atPath: from, toPath: entry.target)
            restoredIDs.insert(entry.id)
            message = "Restored \(name) to its original location."
        } catch {
            message = "Restore failed: \(error.localizedDescription)"
        }
    }
}
