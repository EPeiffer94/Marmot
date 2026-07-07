import SwiftUI

/// System maintenance tasks. Every task shows its exact commands and expected
/// effects before running — and supports dry runs like everything else.
struct MaintenanceView: View {

    @State private var activePlan: ChangePlan?
    @State private var lastRun: [String: Date] = [:]

    private let tasks = MaintenanceCatalog.all

    var body: some View {
        List(tasks) { task in
            HStack(spacing: 14) {
                Image(systemName: task.icon)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(task.name).font(.headline)
                        Badge(risk: task.risk)
                        if task.needsAdmin {
                            Badge(text: "admin", color: .purple)
                        }
                    }
                    Text(task.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(task.effect, systemImage: "arrow.turn.down.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if let last = lastRun[task.id] {
                        Text("Last run \(last.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Button("Review & Run…") {
                    activePlan = task.plan()
                }
            }
            .padding(.vertical, 6)
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .sheet(item: $activePlan) { plan in
            PlanPreviewView(plan: plan) { result in
                if let r = result, !r.dryRun,
                   let task = tasks.first(where: { $0.name == r.planTitle }) {
                    lastRun[task.id] = Date()
                }
                activePlan = nil
            }
        }
        .navigationSubtitle("Each task shows its exact commands before running")
    }
}
