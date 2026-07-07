import SwiftUI

/// Live system dashboard: CPU, GPU, memory, disk, network, battery,
/// top processes, and an overall health score.
struct StatusView: View {

    @EnvironmentObject var stats: StatsSampler

    var snap: SystemSnapshot { stats.snapshot }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                healthHeader
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    cpuCard
                    memoryCard
                    diskCard
                    networkCard
                    batteryOrGPUCard
                    processCard
                }
            }
            .padding()
        }
        .navigationSubtitle("Sampled every 2 seconds")
    }

    // MARK: Health

    private var healthHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(snap.healthScore) / 100)
                    .stroke(snap.healthColor.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(snap.healthScore)")
                    .font(.title2.weight(.bold).monospacedDigit())
            }
            .frame(width: 72, height: 72)
            .animation(.easeOut, value: snap.healthScore)

            VStack(alignment: .leading, spacing: 3) {
                Text("System Health")
                    .font(.title3.weight(.semibold))
                Text(healthDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Uptime \(snap.uptime)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding()
        .background(cardBackground)
    }

    private var healthDescription: String {
        if snap.healthScore >= 90 { return "Running smoothly." }
        if snap.healthScore >= 70 { return "Mostly fine — some load present." }
        if snap.healthScore >= 50 { return "Under pressure. Check CPU, memory, or disk." }
        return "Strained — investigate heavy processes or free up disk space."
    }

    // MARK: Cards

    private var cpuCard: some View {
        card("CPU", icon: "cpu") {
            metricRow("Total", value: String(format: "%.1f%%", snap.cpu.totalUsage),
                      percent: snap.cpu.totalUsage, color: .blue)
            Text(String(format: "Load %.2f / %.2f / %.2f", snap.cpu.loadAvg.0, snap.cpu.loadAvg.1, snap.cpu.loadAvg.2))
                .font(.caption)
                .foregroundStyle(.secondary)
            let columns = [GridItem(.adaptive(minimum: 60), spacing: 6)]
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(snap.cpu.perCore.enumerated()), id: \.offset) { index, usage in
                    VStack(spacing: 1) {
                        PercentBar(percent: usage, color: .blue)
                        Text("C\(index + 1)")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var memoryCard: some View {
        card("Memory", icon: "memorychip") {
            metricRow("Used", value: "\(ByteFormat.string(snap.memory.usedBytes)) / \(ByteFormat.string(snap.memory.totalBytes))",
                      percent: snap.memory.usedPercent, color: .teal)
            HStack(spacing: 14) {
                labeled("App", ByteFormat.string(snap.memory.appBytes))
                labeled("Wired", ByteFormat.string(snap.memory.wiredBytes))
                labeled("Compressed", ByteFormat.string(snap.memory.compressedBytes))
            }
        }
    }

    private var diskCard: some View {
        card("Disk", icon: "internaldrive") {
            metricRow("Used", value: "\(ByteFormat.string(snap.disk.totalBytes - snap.disk.freeBytes)) / \(ByteFormat.string(snap.disk.totalBytes))",
                      percent: snap.disk.usedPercent, color: .orange)
            HStack(spacing: 14) {
                labeled("Free", ByteFormat.string(snap.disk.freeBytes))
                labeled("Read", ByteFormat.rate(snap.disk.readPerSec))
                labeled("Write", ByteFormat.rate(snap.disk.writePerSec))
            }
        }
    }

    private var networkCard: some View {
        card("Network", icon: "arrow.up.arrow.down") {
            HStack(spacing: 14) {
                labeled("Down", ByteFormat.rate(snap.network.downPerSec))
                labeled("Up", ByteFormat.rate(snap.network.upPerSec))
            }
            Sparkline(values: snap.network.downHistory, color: .blue)
                .frame(height: 30)
            Sparkline(values: snap.network.upHistory, color: .green)
                .frame(height: 30)
        }
    }

    private var batteryOrGPUCard: some View {
        card(snap.battery.present ? "Power" : "GPU", icon: snap.battery.present ? "battery.75percent" : "cpu.fill") {
            if snap.battery.present {
                metricRow(snap.battery.isCharging ? "Charging" : "Battery",
                          value: String(format: "%.0f%%", snap.battery.percent),
                          percent: snap.battery.percent,
                          color: snap.battery.percent > 20 ? .green : .red)
                HStack(spacing: 14) {
                    labeled("Health", snap.battery.health)
                }
            }
            if let gpu = snap.gpuUsage {
                metricRow("GPU", value: String(format: "%.0f%%", gpu), percent: gpu, color: .purple)
            } else if !snap.battery.present {
                Text("GPU utilization unavailable on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var processCard: some View {
        card("Top Processes", icon: "list.number") {
            if snap.topProcesses.isEmpty {
                Text("—").foregroundStyle(.secondary)
            }
            ForEach(snap.topProcesses) { process in
                HStack {
                    Text(process.name)
                        .font(.callout)
                        .lineLimit(1)
                    Spacer()
                    Text(String(format: "%.1f%%", process.cpuPercent))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    PercentBar(percent: min(process.cpuPercent, 100), color: .indigo)
                        .frame(width: 70)
                }
            }
        }
    }

    // MARK: Helpers

    private func card<Content: View>(_ title: String, icon: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.primary.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
    }

    private func metricRow(_ label: String, value: String, percent: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Text(value).font(.callout.weight(.medium).monospacedDigit())
            }
            PercentBar(percent: percent, color: color)
        }
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.tertiary)
            Text(value).font(.caption.weight(.medium).monospacedDigit())
        }
    }
}
