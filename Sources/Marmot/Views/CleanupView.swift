import SwiftUI

/// Visual cleanup review: scan the known junk locations, review each category
/// and item, then hand everything to the PlanPreview sheet for dry-run/apply.
struct CleanupView: View {

    @State private var categories: [CleanupCategory] = CleanupScanner.categories()
    @State private var selectedCategoryIDs: Set<String> = []
    @State private var scanning = false
    @State private var scannedOnce = false
    @State private var activePlan: ChangePlan?
    @State private var lastResultSummary: String?

    var totalFound: Int64 { categories.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(spacing: 0) {
            if !scannedOnce && !scanning {
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
                    Task { await rescan() }
                }
            }
        }
        .navigationSubtitle(scannedOnce ? "Found \(ByteFormat.string(totalFound)) of removable data" : "")
    }

    // MARK: Start state

    private var startState: some View {
        StartScreen(icon: "sparkles",
                    title: "Deep Cleanup",
                    message: "Scans caches, logs, browser data, developer junk, orphaned app data, installers, build artifacts, and Trash. Nothing is removed without your review — every change is shown first, and you can dry-run it.",
                    buttonLabel: "Scan My Mac") {
            Task { await rescan() }
        }
    }

    // MARK: Category list

    private var categoryList: some View {
        List {
            if let summary = lastResultSummary {
                Label(summary, systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
            ForEach(categories) { category in
                categoryRow(category)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func categoryRow(_ category: CleanupCategory) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { selectedCategoryIDs.contains(category.id) },
                set: { on in
                    if on { selectedCategoryIDs.insert(category.id) }
                    else { selectedCategoryIDs.remove(category.id) }
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
            if scanning {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await rescan() }
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .disabled(scanning)

            Button {
                reviewCategories(Array(selectedCategoryIDs))
            } label: {
                Label("Review Selected…", systemImage: "eye")
            }
            .disabled(selectedCategoryIDs.isEmpty || scanning)
            .help("Opens the change preview for all selected categories. You can dry-run before applying.")
        }
    }

    // MARK: Actions

    @MainActor
    private func rescan() async {
        scanning = true
        scannedOnce = true
        lastResultSummary = nil
        for i in categories.indices { categories[i].isScanning = true; categories[i].items = [] }

        let base = CleanupScanner.categories()
        await withTaskGroup(of: (Int, [ChangeItem]).self) { group in
            for (index, category) in base.enumerated() {
                group.addTask {
                    let items = CleanupScanner.scan(categoryID: category.id)
                    return (index, items)
                }
            }
            for await (index, items) in group {
                categories[index].items = items
                categories[index].isScanning = false
                if !items.isEmpty { selectedCategoryIDs.insert(categories[index].id) }
            }
        }
        scanning = false
    }

    private func reviewCategories(_ ids: [String]) {
        let selected = categories.filter { ids.contains($0.id) }
        let items = selected.flatMap(\.items)
        guard !items.isEmpty else { return }
        let names = selected.map(\.name).joined(separator: ", ")
        activePlan = ChangePlan(
            title: selected.count == 1 ? "Clean \(names)" : "Clean \(selected.count) Categories",
            source: "Cleanup",
            items: items)
    }
}
