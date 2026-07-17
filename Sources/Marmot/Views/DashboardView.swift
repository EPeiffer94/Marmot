import SwiftUI
import Charts
import AppKit

/// Home screen: system health at a glance, reclaimable space from the shared
/// cleanup model (instant thanks to the persisted cache), and shortcuts into
/// every module.
struct DashboardView: View {

    @EnvironmentObject var stats: StatsSampler
    @ObservedObject private var cleanup = CleanupModel.shared
    @ObservedObject private var trends = TrendStore.shared
    @ObservedObject private var inventory = AppInventory.shared
    @State private var freedStats: FreedStats?
    @State private var suggestions: [Suggestion] = []
    @AppStorage(Prefs.supporter) private var supporter = false
    @State private var showWrapped = false
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
                if !suggestions.isEmpty {
                    suggestionsCard
                }
                if let stats = freedStats, !stats.isEmpty {
                    reportCard(stats)
                }
                if trends.points.count >= 2 {
                    trendsCard
                }
                moduleGrid
            }
            .padding()
        }
        .onAppear {
            inventory.loadIfNeeded()
            Task { @MainActor in
                freedStats = await Task.detached { OperationLog.shared.freedStats() }.value
            }
            refreshSuggestions()
        }
        .onChange(of: cleanup.lastScan) { _ in refreshSuggestions() }
        .sheet(isPresented: $showWrapped) {
            WrappedView(stats: Wrapped.stats(from: OperationLog.shared.readAll())) {
                showWrapped = false
            }
        }
        .navigationSubtitle("Welcome to Marmot")
    }

    private func refreshSuggestions() {
        let categories = cleanup.categories
        let apps = inventory.apps
        let free = snap.disk.freeBytes
        let total = snap.disk.totalBytes
        let hasRules = Autopilot.shared.rules.contains { $0.isEnabled }
        Task { @MainActor in
            suggestions = await Task.detached(priority: .utility) {
                SuggestionEngine.compute(categories: categories, apps: apps,
                                         diskFree: free, diskTotal: total,
                                         historyEntries: OperationLog.shared.readAll(),
                                         hasAutopilotRules: hasRules)
            }.value
        }
    }

    // MARK: Suggestions

    private var suggestionsCard: some View {
        card(tint: .pink) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Suggestions", systemImage: "lightbulb")
                    .font(.headline)
                ForEach(suggestions) { suggestion in
                    Button {
                        onNavigate(suggestion.target)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: suggestion.icon)
                                .foregroundStyle(.tint)
                                .frame(width: 20)
                            Text(suggestion.text)
                                .font(.callout)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Report card

    private func reportCard(_ stats: FreedStats) -> some View {
        card(tint: .mint) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Report Card", systemImage: "chart.bar.doc.horizontal")
                        .font(.headline)
                    Spacer()
                    Button("Wrapped ✨") { showWrapped = true }
                        .controlSize(.small)
                        .help("Your cleaning stats as a shareable card.")
                }
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
                // Gentle, dismissible tip-jar nudge — only once Marmot has
                // genuinely earned it, never for supporters.
                if !supporter, stats.allTime > 10_000_000_000 {
                    Button {
                        NSWorkspace.shared.open(Support.sponsorsURL ?? Support.repoURL)
                    } label: {
                        Label("Marmot has freed \(ByteFormat.string(stats.allTime)) for you — feed the marmot? 🐿️",
                              systemImage: "heart")
                            .font(.caption)
                            .foregroundStyle(.pink)
                    }
                    .buttonStyle(.plain)
                    .help("Marmot is free forever. This hides permanently via Settings → Support.")
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
        card(tint: .mint) {
            HStack(spacing: 16) {
                HealthRing(score: snap.healthScore, lineWidth: 9, caption: "health")
                    .frame(width: 92, height: 92)

                VStack(alignment: .leading, spacing: 8) {
                    miniMetric("cpu", "CPU", snap.cpu.totalUsage, .blue)
                    miniMetric("memorychip", "Memory", snap.memory.usedPercent, .teal)
                    miniMetric("internaldrive", "Disk", snap.disk.usedPercent, .cyan)
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
        card(tint: .green) {
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

    // MARK: Trends

    private var trendsCard: some View {
        card(tint: .blue) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Storage Trends", systemImage: "chart.xyaxis.line")
                    .font(.headline)

                Chart {
                    ForEach(trends.points) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("GB", Double(point.diskUsed) / 1_000_000_000),
                            series: .value("Metric", "Disk used")
                        )
                        .foregroundStyle(.blue)
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("GB", Double(point.junkTotal) / 1_000_000_000),
                            series: .value("Metric", "Reclaimable junk")
                        )
                        .foregroundStyle(.pink)
                    }
                }
                .frame(height: 110)

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Circle().fill(.blue).frame(width: 7, height: 7)
                        Text("Disk used (GB)").font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(.pink).frame(width: 7, height: 7)
                        Text("Reclaimable junk (GB)").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if let days = trends.forecastDaysUntilFull {
                    Label("At this pace, the disk could fill in about \(days) day\(days == 1 ? "" : "s")",
                          systemImage: "hourglass")
                        .font(.caption)
                        .foregroundStyle(.pink)
                }

                let movers = trends.movers()
                if !movers.isEmpty {
                    HStack(spacing: 16) {
                        Text("Since last scan:")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        ForEach(movers, id: \.name) { mover in
                            HStack(spacing: 3) {
                                Image(systemName: mover.delta > 0 ? "arrow.up.right" : "arrow.down.right")
                                    .font(.caption2)
                                    .foregroundStyle(mover.delta > 0 ? .pink : .green)
                                Text("\(mover.name) \(mover.delta > 0 ? "+" : "−")\(ByteFormat.string(abs(mover.delta)))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Theme.color(for: section).gradient)
                            )
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
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Theme.wash(Theme.color(for: section)))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Card chrome

    private func card<Content: View>(tint: Color? = nil,
                                     @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .cardStyle(tint: tint)
    }
}
