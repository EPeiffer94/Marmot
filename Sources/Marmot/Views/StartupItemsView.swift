import SwiftUI

/// Startup items manager: login items, launch agents, and daemons — with
/// explanations and plan-previewed removal.
struct StartupItemsView: View {

    @State private var items: [StartupItem] = []
    @State private var loading = false
    @State private var loadedOnce = false
    @State private var activePlan: ChangePlan?

    var body: some View {
        Group {
            if loading && items.isEmpty {
                ProgressView("Reading startup items…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if loadedOnce && items.isEmpty {
                EmptyState(icon: "power",
                           title: "Nothing starts automatically",
                           message: "No third-party login items, launch agents, or daemons were found.")
            } else {
                itemList
            }
        }
        .toolbar {
            ToolbarItemGroup {
                if loading { ProgressView().controlSize(.small) }
                Button {
                    load()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(loading)
            }
        }
        .sheet(item: $activePlan) { plan in
            PlanPreviewView(plan: plan) { result in
                activePlan = nil
                if let r = result, !r.dryRun { load() }
            }
        }
        .onAppear { if !loadedOnce { load() } }
        .navigationSubtitle("\(items.count) startup items")
    }

    private var itemList: some View {
        List {
            Label("Fewer startup items = faster boot and less background load. Removing an entry never deletes the app itself.",
                  systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(StartupItem.Kind.allCases, id: \.self) { kind in
                let kindItems = items.filter { $0.kind == kind }
                if !kindItems.isEmpty {
                    Section(kind.rawValue) {
                        ForEach(kindItems) { item in
                            itemRow(item)
                        }
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func itemRow(_ item: StartupItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconName(item.kind))
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name).font(.headline)
                    if item.keepAlive {
                        badge("always running", .orange)
                    } else if item.runAtLoad {
                        badge("runs at login", .blue)
                    }
                    if item.kind == .systemAgent || item.kind == .systemDaemon {
                        badge("admin to remove", .purple)
                    }
                }
                Text(item.detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button("Remove…") {
                activePlan = StartupEngine.removalPlan(for: item)
            }
        }
        .padding(.vertical, 3)
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func iconName(_ kind: StartupItem.Kind) -> String {
        switch kind {
        case .loginItem: return "person.crop.circle"
        case .userAgent: return "figure.walk"
        case .systemAgent: return "person.3"
        case .systemDaemon: return "gearshape.2"
        }
    }

    private func load() {
        loading = true
        loadedOnce = true
        Task.detached(priority: .userInitiated) {
            let found = StartupEngine.all()
            await MainActor.run {
                items = found
                loading = false
            }
        }
    }
}
