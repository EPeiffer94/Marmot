import SwiftUI

/// Home screen: system health at a glance, reclaimable space from the shared
/// cleanup model (instant thanks to the persisted cache), and shortcuts into
/// every module.
struct DashboardView: View {

    @EnvironmentObject var stats: StatsSampler
    @ObservedObject private var cleanup = CleanupModel.shared
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
                moduleGrid
            }
            .padding()
        }
        .navigationSubtitle("Welcome to Marmot")
    }

    // MARK: Health

    private var healthCard: some View {
        card {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: CGFloat(snap.healthScore) / 100)
                        .stroke(snap.healthColor.gradient,
                                style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(snap.healthScore)")
                            .font(.title.weight(.bold).monospacedDigit())
                        Text("health")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 92, height: 92)
                .animation(.easeOut, value: snap.healthScore)

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
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.primary.opacity(0.06))
                    )
            )
    }
}
