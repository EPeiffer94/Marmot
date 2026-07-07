import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case cleanup = "Cleanup"
    case uninstall = "Uninstaller"
    case updates = "App Updates"
    case diskMap = "Disk Map"
    case maintenance = "Maintenance"
    case status = "Live Status"
    case history = "History"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .cleanup: return "sparkles"
        case .uninstall: return "trash.square"
        case .updates: return "arrow.down.app"
        case .diskMap: return "square.grid.3x3.topleft.filled"
        case .maintenance: return "wrench.and.screwdriver"
        case .status: return "gauge.with.needle"
        case .history: return "clock.arrow.circlepath"
        }
    }
}

struct MainWindow: View {
    @State private var selection: SidebarSection? = .cleanup
    @EnvironmentObject var stats: StatsSampler

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .safeAreaInset(edge: .bottom) {
                sidebarFooter
            }
        } detail: {
            switch selection ?? .cleanup {
            case .cleanup: CleanupView()
            case .uninstall: UninstallView()
            case .updates: UpdatesView()
            case .diskMap: DiskMapView()
            case .maintenance: MaintenanceView()
            case .status: StatusView()
            case .history: HistoryView()
            }
        }
        .navigationTitle("Marmot")
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack(spacing: 6) {
                Circle()
                    .fill(healthColor)
                    .frame(width: 8, height: 8)
                Text("Health \(stats.snapshot.healthScore)")
                    .font(.caption.weight(.medium))
                Spacer()
                Text("CPU \(Int(stats.snapshot.cpu.totalUsage))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
    }

    private var healthColor: Color {
        let score = stats.snapshot.healthScore
        if score >= 80 { return .green }
        if score >= 50 { return .orange }
        return .red
    }
}
