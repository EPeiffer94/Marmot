import SwiftUI

/// Visual cleanup review: scan the known junk locations, review each category
/// and item, then hand everything to the PlanPreview sheet for dry-run/apply.
/// Results come from the shared CleanupModel, so cached numbers appear
/// instantly and the Dashboard stays in sync.
struct CleanupView: View {

    @ObservedObject private var model = CleanupModel.shared
    @State private var selectedCategoryIDs: Set<String> = []
    @State private var activePlan: ChangePlan?
    @State private var lastResultSummary: String?

    var body: some View {
        VStack(spacing: 0) {
            if !model.scannedOnce && !model.scanning {
                startState
            } else {
                categoryList
            }
        }
        .toolbar { toolbarContent }
        .sheet(item: $activePlan) { plan in
            PlanPreviewView(plan: plan, allowPurgeRoots: true) { result in
                activePlan = nil
                if let r = result, !r.dryRun {
                    lastResultSummary = "Freed \(ByteFormat.string(r.freedBytes))"
                    model.rescan()
                }
            }
        }
        .onAppear {
            if selectedCategoryIDs.isEmpty {
                selectedCategoryIDs = model.nonEmptyCategoryIDs
            }
        }
        .onChange(of: model.scanning) { isScanning in
            if !isScanning {
                selectedCategoryIDs = model.nonEmptyCategoryIDs
            }
        }
        .navigationSubtitle(subtitle)
    }

    private var subtitle: String {
        guard model.scannedOnce else { return "" }
        var text = "Found \(ByteFormat.string(model.totalFound)) of removable data"
        if let date = model.lastScan, !model.scanning {
            text += " — scanned \(date.formatted(.relative(presentation: .named)))"
        }
        return text
    }

    // MARK: Start state

    private var startState: some View {
        StartScreen(icon: "sparkles",
                    title: "Deep Cleanup",
                    message: "Scans caches, logs, browser data, developer junk, orphaned app data, "
                        + "installers, build artifacts, and Trash. Nothing is removed without your "
                        + "review — every change is shown first, and you can dry-run it.",
                    buttonLabel: "Scan My Mac",
                    tint: Theme.color(for: .cleanup)) {
            model.rescan()
        }
    }

    // MARK: Category list

    private var categoryList: some View {
        List {
            if let summary = lastResultSummary {
                Label(summary, systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
            ForEach(model.categories) { category in
                categoryRow(category)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .animation(.default, value: model.totalFound)
    }

    private func categoryRow(_ category: CleanupCategory) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { selectedCategoryIDs.contains(category.id) },
                set: { on in
                    if on {
                        selectedCategoryIDs.insert(category.id)
                    } else {
                        selectedCategoryIDs.remove(category.id)
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(category.items.isEmpty)

            Image(systemName: category.icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(category.name).font(.headline)
                Text(category.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if category.isScanning {
                ProgressView().controlSize(.small)
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ByteFormat.string(category.size))
                        .font(.callout.weight(.semibold).monospacedDigit())
                    Text("\(category.items.count) items")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Button("Review…") {
                reviewCategories([category.id])
            }
            .disabled(category.items.isEmpty)
        }
        .padding(.vertical, 4)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            if model.scanning {
                ProgressView().controlSize(.small)
            }
            Button {
                model.rescan()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.scanning)

            Button {
                reviewCategories(Array(selectedCategoryIDs))
            } label: {
                Label("Review Selected…", systemImage: "eye")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(selectedCategoryIDs.isEmpty || model.scanning)
            .help("Opens the change preview for all selected categories. You can dry-run before applying.")
        }
    }

    // MARK: Actions

    private func reviewCategories(_ ids: [String]) {
        let selected = model.categories.filter { ids.contains($0.id) }
        let items = selected.flatMap(\.items)
        guard !items.isEmpty else { return }
        let names = selected.map(\.name).joined(separator: ", ")
        activePlan = ChangePlan(
            title: selected.count == 1 ? "Clean \(names)" : "Clean \(selected.count) Categories",
            source: "Cleanup",
            items: items)
    }
}
