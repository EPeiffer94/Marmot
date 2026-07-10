import SwiftUI
import AppKit

/// Apps you haven't opened in months, with their disk footprint —
/// one click to the full uninstall plan.
struct UnusedAppsView: View {

    @ObservedObject private var inventory = AppInventory.shared
    @State private var months = 6
    @State private var activePlan: ChangePlan?
    @State private var buildingPlan = false

    private var cutoff: Date {
        Calendar.current.date(byAdding: .month, value: -months, to: Date()) ?? Date()
    }

    private var unused: [InstalledApp] {
        inventory.apps.filter { app in
            guard app.bundleID.lowercased() != "dev.marmot.app" else { return false }
            guard let used = app.lastUsed else { return true }
            return used < cutoff
        }
        .sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private var totalSize: Int64 { unused.reduce(0) { $0 + $1.sizeBytes } }

    var body: some View {
        Group {
            if inventory.loading && inventory.apps.isEmpty {
                LoadingState(text: "Checking when each app was last opened…")
            } else if unused.isEmpty {
                EmptyState(icon: "hourglass",
                           title: "No unused apps",
                           message: "Everything installed has been opened within the last \(months) months. 👏")
            } else {
                appList
            }
        }
        .toolbar {
            ToolbarItemGroup {
                if buildingPlan { ProgressView().controlSize(.small) }
                Picker("Unused for", selection: $months) {
                    Text("3 months").tag(3)
                    Text("6 months").tag(6)
                    Text("12 months").tag(12)
                }
                .pickerStyle(.segmented)
                Button {
                    inventory.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .sheet(item: $activePlan) { plan in
            PlanPreviewView(plan: plan) { result in
                activePlan = nil
                if let r = result, !r.dryRun { inventory.refresh() }
            }
        }
        .onAppear { inventory.loadIfNeeded() }
        .navigationSubtitle("\(unused.count) apps unused for \(months)+ months — \(ByteFormat.string(totalSize))")
    }

    private var appList: some View {
        List {
            Label("\"Last used\" comes from Spotlight metadata. Uninstalling opens the full removal plan — app plus every leftover — with dry-run available.",
                  systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(unused) { app in
                HStack(spacing: 12) {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 30, height: 30)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(.headline)
                        Text(app.lastUsed.map {
                            "Last used \($0.formatted(date: .abbreviated, time: .omitted))"
                        } ?? "Never opened (per Spotlight)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(app.sizeBytes > 0 ? ByteFormat.string(app.sizeBytes) : "…")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button("Uninstall…") {
                        buildPlan(for: app)
                    }
                    .disabled(buildingPlan)
                }
                .padding(.vertical, 3)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func buildPlan(for app: InstalledApp) {
        buildingPlan = true
        Task { @MainActor in
            let plan = await Task.detached(priority: .userInitiated) {
                UninstallEngine.uninstallPlan(for: app)
            }.value
            buildingPlan = false
            activePlan = plan
        }
    }
}
