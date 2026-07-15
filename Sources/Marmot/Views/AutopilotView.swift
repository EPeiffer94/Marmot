import SwiftUI

/// Scheduled cleaning rules. Rules only cover categories the user picks;
/// every run is trash-first, logged in History, and announced.
struct AutopilotView: View {

    @ObservedObject private var autopilot = Autopilot.shared
    @State private var editingRule: AutopilotRule?
    @State private var showingNewRule = false

    var body: some View {
        Group {
            if autopilot.rules.isEmpty {
                StartScreen(icon: "clock.badge.checkmark",
                            title: "Autopilot",
                            message: "Write cleaning rules once — \"clear browser caches weekly\", "
                                + "\"empty developer junk monthly\" — and Marmot runs them on schedule. "
                                + "Runs are trash-first, logged in History, and announced with a "
                                + "notification. Build artifacts and orphaned data stay manual-only.",
                            buttonLabel: "Create First Rule",
                            tint: .indigo) {
                    showingNewRule = true
                }
            } else {
                ruleList
            }
        }
        .toolbar {
            ToolbarItemGroup {
                if autopilot.running { ProgressView().controlSize(.small) }
                Button {
                    showingNewRule = true
                } label: {
                    Label("New Rule", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewRule) {
            RuleEditor(rule: AutopilotRule(name: "", categoryIDs: [], frequency: .weekly,
                                           createdAt: Date())) { rule in
                autopilot.rules.append(rule)
            }
        }
        .sheet(item: $editingRule) { rule in
            RuleEditor(rule: rule) { updated in
                if let index = autopilot.rules.firstIndex(where: { $0.id == updated.id }) {
                    autopilot.rules[index] = updated
                }
            }
        }
        .navigationSubtitle("\(autopilot.rules.count) rules")
    }

    private var ruleList: some View {
        List {
            Label("Rules run while Marmot is open (keep the menu bar HUD on). Every run goes to the Trash and shows up in History — undo anytime.",
                  systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(autopilot.rules) { rule in
                ruleRow(rule)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func ruleRow(_ rule: AutopilotRule) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { on in
                    if let index = autopilot.rules.firstIndex(where: { $0.id == rule.id }) {
                        autopilot.rules[index].isEnabled = on
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(rule.name.isEmpty ? "Untitled rule" : rule.name)
                        .font(.headline)
                    Badge(text: rule.frequency.rawValue, color: .blue)
                }
                Text(categorySummary(rule))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(lastRunSummary(rule))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Run Now") {
                autopilot.run(rule)
            }
            .disabled(autopilot.running || !rule.isEnabled)
            Button("Edit…") {
                editingRule = rule
            }
            Button(role: .destructive) {
                autopilot.rules.removeAll { $0.id == rule.id }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .opacity(rule.isEnabled ? 1 : 0.55)
    }

    private func categorySummary(_ rule: AutopilotRule) -> String {
        let names = Dictionary(uniqueKeysWithValues: CleanupScanner.categories().map { ($0.id, $0.name) })
        return rule.categoryIDs.compactMap { names[$0] }.joined(separator: ", ")
    }

    private func lastRunSummary(_ rule: AutopilotRule) -> String {
        guard let last = rule.lastRun else { return "Never run yet" }
        var text = "Last run \(last.formatted(.relative(presentation: .named)))"
        if rule.lastFreedBytes > 0 {
            text += " — freed \(ByteFormat.string(rule.lastFreedBytes))"
        }
        return text
    }
}

// MARK: - Rule editor

struct RuleEditor: View {

    @State var rule: AutopilotRule
    var onSave: (AutopilotRule) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Rule name", text: $rule.name, prompt: Text("e.g. Weekly cache sweep"))
                Picker("Runs", selection: $rule.frequency) {
                    ForEach(AutopilotRule.Frequency.allCases, id: \.self) { freq in
                        Text(freq.rawValue).tag(freq)
                    }
                }
                Section("Clean these categories") {
                    ForEach(Autopilot.eligibleCategories) { category in
                        Toggle(isOn: Binding(
                            get: { rule.categoryIDs.contains(category.id) },
                            set: { on in
                                if on {
                                    rule.categoryIDs.append(category.id)
                                } else {
                                    rule.categoryIDs.removeAll { $0 == category.id }
                                }
                            }
                        )) {
                            HStack(spacing: 6) {
                                Text(category.name)
                                if category.id == "trash" {
                                    Badge(text: "permanent", color: .red)
                                }
                            }
                        }
                    }
                }
                if rule.categoryIDs.contains("trash") {
                    Text("Heads up: emptying the Trash is permanent — those items can't be restored afterwards.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save Rule") {
                    onSave(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(rule.categoryIDs.isEmpty)
            }
            .padding()
        }
        .frame(width: 440, height: 480)
    }
}
