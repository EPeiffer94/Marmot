import SwiftUI

/// Operation history — every applied change and every dry run, from the
/// append-only JSONL log.
struct HistoryView: View {

    @State private var entries: [LogEntry] = []
    @State private var filter: Filter = .all

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
        Group {
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
}
