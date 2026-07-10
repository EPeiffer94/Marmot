import SwiftUI

/// The heart of Marmot: every destructive operation passes through this sheet.
/// It shows exactly what will change, lets the user deselect items, run a
/// dry run, and only then apply — with live progress and a results report.
struct PlanPreviewView: View {

    enum Phase {
        case reviewing
        case running(progress: Double, current: String)
        case finished(ExecutionResult)
    }

    @State var plan: ChangePlan
    var allowPurgeRoots = false
    var allowUserFiles = false
    var onDismiss: (ExecutionResult?) -> Void

    @State private var phase: Phase = .reviewing
    @State private var confirmApply = false
    @AppStorage(Prefs.defaultDryRun) private var defaultDryRun = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch phase {
            case .reviewing:
                reviewBody
            case .running(let progress, let current):
                runningBody(progress: progress, current: current)
            case .finished(let result):
                ResultsView(result: result)
            }
            Divider()
            footer
        }
        .frame(width: 720, height: 560)
        .confirmationDialog(
            "Apply \(plan.title)?",
            isPresented: $confirmApply,
            titleVisibility: .visible
        ) {
            // The Settings toggle controls which action leads: cautious users
            // get the dry run offered first.
            if defaultDryRun {
                Button("Run as Dry Run First") { run(dryRun: true) }
                Button("Apply — \(plan.summary)", role: .destructive) { run(dryRun: false) }
            } else {
                Button("Apply — \(plan.summary)", role: .destructive) { run(dryRun: false) }
                Button("Run as Dry Run Instead") { run(dryRun: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(applyWarning)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(plan.title, systemImage: "list.bullet.clipboard")
                    .font(.title3.weight(.semibold))
                Spacer()
                if case .reviewing = phase {
                    Text(plan.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            if case .reviewing = phase, plan.selectedSize > 0 {
                ProportionBar(shares: groupShares)
            }
        }
        .padding()
    }

    private var groupShares: [GroupShare] {
        let grouped = Dictionary(grouping: plan.selectedItems, by: \.group)
        return grouped
            .map { (name: $0.key, bytes: $0.value.reduce(Int64(0)) { $0 + $1.sizeBytes }) }
            .sorted { $0.bytes > $1.bytes }
            .enumerated()
            .map { GroupShare(name: $1.name, bytes: $1.bytes, color: Palette.color(for: $0)) }
    }

    // MARK: Review list

    private var reviewBody: some View {
        List {
            ForEach(plan.groups, id: \.self) { group in
                Section(header: groupHeader(group)) {
                    ForEach(itemIndices(in: group), id: \.self) { index in
                        itemRow(index: index)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func itemIndices(in group: String) -> [Int] {
        plan.items.indices.filter { plan.items[$0].group == group }
    }

    private func groupHeader(_ group: String) -> some View {
        let items = plan.items.filter { $0.group == group }
        let size = items.reduce(Int64(0)) { $0 + $1.sizeBytes }
        return HStack {
            Text(group)
            Spacer()
            Text("\(items.count) items · \(ByteFormat.string(size))")
                .foregroundStyle(.secondary)
        }
        .font(.caption.weight(.semibold))
    }

    private func itemRow(index: Int) -> some View {
        let item = plan.items[index]
        return HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(
                get: { plan.items[index].isSelected },
                set: { plan.items[index].isSelected = $0 }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Image(systemName: iconName(for: item))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(item.displayName)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Badge(risk: item.risk)
                    if item.action == .runAdminCommand {
                        Badge(text: "admin", color: .purple)
                    }
                }
                if !item.note.isEmpty {
                    Text(item.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(item.target)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            if item.sizeBytes > 0 {
                Text(ByteFormat.string(item.sizeBytes))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .opacity(item.isSelected ? 1 : 0.45)
    }

    private func iconName(for item: ChangeItem) -> String {
        switch item.action {
        case .moveToTrash: return "trash"
        case .deletePermanently: return "xmark.bin"
        case .runCommand, .runAdminCommand: return "terminal"
        }
    }

    // MARK: Running

    private func runningBody(progress: Double, current: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView(value: progress)
                .frame(width: 380)
            Text(current)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 420)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            switch phase {
            case .reviewing:
                Button("Select All") { setAll(true) }
                Button("Select None") { setAll(false) }
                Spacer()
                Text("Selected: \(ByteFormat.string(plan.selectedSize))")
                    .font(.callout.weight(.medium).monospacedDigit())
                Button {
                    run(dryRun: true)
                } label: {
                    Label("Dry Run", systemImage: "eye")
                }
                .help("Simulates the plan. Nothing on disk is touched; results show what would happen.")
                Button {
                    confirmApply = true
                } label: {
                    Label("Apply", systemImage: "checkmark.circle.fill")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(plan.selectedItems.isEmpty)
                Button("Cancel") { dismiss(); onDismiss(nil) }

            case .running:
                Spacer()
                Text("Working…").foregroundStyle(.secondary)
                Spacer()

            case .finished(let result):
                if result.dryRun {
                    Label("Dry run — nothing was changed", systemImage: "eye")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Back to Review") { phase = .reviewing }
                    Button {
                        confirmApply = true
                    } label: {
                        Label("Apply for Real", systemImage: "checkmark.circle.fill")
                    }
                    Button("Close") { dismiss(); onDismiss(result) }
                } else {
                    Spacer()
                    Button("Done") { dismiss(); onDismiss(result) }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding()
    }

    private var applyWarning: String {
        let trash = plan.selectedItems.filter { $0.action == .moveToTrash }
        let perm = plan.selectedItems.filter { $0.action == .deletePermanently }
        let cmds = plan.selectedItems.filter { $0.action == .runCommand || $0.action == .runAdminCommand }
        var lines: [String] = []
        if !trash.isEmpty { lines.append("\(trash.count) items move to Trash (recoverable).") }
        if !perm.isEmpty { lines.append("\(perm.count) items are deleted permanently.") }
        if !cmds.isEmpty { lines.append("\(cmds.count) commands run\(cmds.contains { $0.action == .runAdminCommand } ? ", some with admin privileges" : "").") }
        if plan.highestRisk == .high { lines.append("⚠ This plan contains high-risk items.") }
        return lines.joined(separator: "\n")
    }

    private func setAll(_ value: Bool) {
        for i in plan.items.indices {
            if value && plan.items[i].risk == .high { continue }
            plan.items[i].isSelected = value
        }
    }

    private func run(dryRun: Bool) {
        phase = .running(progress: 0, current: "Starting…")
        let planCopy = plan
        let purge = allowPurgeRoots
        let userFiles = allowUserFiles
        Task {
            let result = await PlanExecutor.execute(planCopy, dryRun: dryRun,
                                                    allowPurgeRoots: purge,
                                                    allowUserFiles: userFiles) { progress, name in
                Task { @MainActor in
                    phase = .running(progress: progress, current: name)
                }
            }
            await MainActor.run {
                phase = .finished(result)
            }
        }
    }
}

// MARK: - Results report

struct ResultsView: View {
    let result: ExecutionResult

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                summaryStat(
                    icon: result.dryRun ? "eye" : "checkmark.seal.fill",
                    color: result.dryRun ? .blue : .green,
                    title: result.dryRun ? "Would free" : "Freed",
                    value: ByteFormat.string(result.dryRun ? result.wouldFreeBytes : result.freedBytes))
                summaryStat(icon: "list.bullet", color: .secondary,
                            title: "Items processed", value: "\(result.results.count)")
                if !result.failures.isEmpty {
                    summaryStat(icon: "exclamationmark.triangle.fill", color: .orange,
                                title: "Failures", value: "\(result.failures.count)")
                }
            }
            .padding()

            List(result.results) { r in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: r.outcome.icon)
                        .foregroundStyle(r.outcome.color)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.item.displayName)
                            .font(.callout)
                            .lineLimit(1).truncationMode(.middle)
                        HStack(spacing: 6) {
                            Text(r.outcome.rawValue).font(.caption).foregroundStyle(.secondary)
                            if !r.detail.isEmpty {
                                Text("— " + r.detail)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer()
                    if r.item.sizeBytes > 0 {
                        Text(ByteFormat.string(r.item.sizeBytes))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func summaryStat(icon: String, color: Color, title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color).font(.title3)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.headline.monospacedDigit())
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

}
