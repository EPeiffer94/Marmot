import SwiftUI

/// Home screen: system health at a glance, reclaimable space from the shared
/// cleanup model (instant thanks to the persisted cache), and shortcuts into
/// every module.
struct DashboardView: View {

    @EnvironmentObject var stats: StatsSampler
    @ObservedObject private var cleanup = CleanupModel.shared
    @State private var freedStats: FreedStats?
    var onNavigate: (SidebarSection) -> Void

    var snap: SystemSnapshot { stats.snapshot }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    healthCard
                    reclaimableCard
                }
                .frame(height: 200)
                if let stats = freedStats, !stats.isEmpty {
                    reportCard(stats)
                }
                moduleGrid
            }
            .padding()
        }
        .onAppear {
            Task { @MainActor in
                freedStats = await Task.detached { OperationLog.shared.freedStats() }.value
            }
        }
        .navigationSubtitle("Welcome to Marmot")
    }

    // MARK: Report card

    private func reportCard(_ stats: FreedStats) -> some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Label("Report Card", systemImage: "chart.bar.doc.horizontal")
                    .font(.headline)
                HStack(spacing: 28) {
                    reportStat("This week", stats.last7Days)
                    reportStat("Last 30 days", stats.last30Days)
                    reportStat("All time", stats.allTime)
                    if let best = stats.biggestRecent {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Biggest recent win")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text("\((best.target as NSString).lastPathComponent) — \(ByteFormat.string(best.sizeBytes))")
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onTapGesture { onNavigate(.history) }
    }

    private func reportStat(_ label: String, _ bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(ByteFormat.string(bytes) + " freed")
                .font(.callout.weight(.semibold).monospacedDigit())
        }
    }

    // MARK: Health

    private var healthCard: some View {
        card {
            HStack(spacing: 16) {
                HealthRing(score: snap.healthScore, lineWidth: 9, caption: "health")
                    .frame(width: 92, height: 92)

                VStack(alignment: .leading, spacing: 8) {
                    miniMetric("cpu", "CPU", snap.cpu.totalUsage, .blue)
                    miniMetric("memorychip", "Memory", snap.memory.usedPercent, .teal)
                    miniMetric("internaldrive", "Disk", snap.disk.usedPercent, .orange)
                    Text("Uptime \(snap.uptime)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
        }
        .onTapGesture { onNavigate(.status) }
    }

    private func miniMetric(_ icon: String, _ label: String, _ percent: Double, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 15)
            PercentBar(percent: percent, color: color)
                .frame(width: 110)
            Text("\(Int(percent))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    // MARK: Reclaimable space

    private var reclaimableCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Label("Reclaimable Space", systemImage: "sparkles")
                    .font(.headline)

                if cleanup.scannedOnce {
                    Text(ByteFormat.string(cleanup.totalFound))
                        .font(.system(size: 34, weight: .bold).monospacedDigit())
                        .contentTransition(.numericText())
                    if cleanup.totalFound > 0 {
                        ProportionBar(shares: categoryShares)
                    }
                    HStack {
                        if let date = cleanup.lastScan {
                            Text("Scanned \(date.formatted(.relative(presentation: .named)))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        smartScanButton
                        Button("Review & Clean…") { onNavigate(.cleanup) }
                            .disabled(cleanup.totalFound == 0)
                    }
                } else {
                    Text("Find out how much space caches, logs, leftovers, and old junk are hoarding — nothing is removed without your review.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    HStack {
                        Spacer()
                        smartScanButton
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var smartScanButton: some View {
        Button {
            cleanup.rescan()
        } label: {
            if cleanup.scanning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Scanning…")
                }
            } else {
                Label("Smart Scan", systemImage: "wand.and.stars")
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(cleanup.scanning)
    }

    private var categoryShares: [GroupShare] {
        cleanup.categories
            .filter { $0.size > 0 }
            .sorted { $0.size > $1.size }
            .enumerated()
            .map { GroupShare(name: $1.name, bytes: $1.size, color: Palette.color(for: $0)) }
    }

    // MARK: Module shortcuts

    private var moduleGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
            ForEach(SidebarSection.allCases.filter { $0 != .dashboard }) { section in
                Button {
                    onNavigate(section)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.icon)
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(section.rawValue)
                                .font(.callout.weight(.medium))
                            Text(section.blurb)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Card chrome

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .cardStyle()
    }
}
