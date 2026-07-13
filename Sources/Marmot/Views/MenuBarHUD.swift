import SwiftUI
import AppKit

/// Compact always-available HUD in the menu bar.
struct MenuBarHUD: View {

    @EnvironmentObject var stats: StatsSampler
    @ObservedObject private var cleanup = CleanupModel.shared

    var snap: SystemSnapshot { stats.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Marmot", systemImage: "gauge.with.needle")
                    .font(.headline)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(snap.healthColor).frame(width: 8, height: 8)
                    Text("Health \(snap.healthScore)")
                        .font(.caption.weight(.semibold))
                }
            }

            Divider()

            row("cpu", "CPU", String(format: "%.0f%%", snap.cpu.totalUsage), snap.cpu.totalUsage, .blue)
            row("memorychip", "Memory", String(format: "%.0f%%", snap.memory.usedPercent), snap.memory.usedPercent, .teal)
            row("internaldrive", "Disk", "\(ByteFormat.string(snap.disk.freeBytes)) free", snap.disk.usedPercent, .orange)

            HStack(spacing: 10) {
                Label(ByteFormat.rate(snap.network.downPerSec), systemImage: "arrow.down")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Label(ByteFormat.rate(snap.network.upPerSec), systemImage: "arrow.up")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if snap.battery.present {
                    Label(String(format: "%.0f%%", snap.battery.percent),
                          systemImage: snap.battery.isCharging ? "battery.100percent.bolt" : "battery.75percent")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if cleanup.scannedOnce {
                Divider()
                HStack {
                    Label("Reclaimable junk", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(ByteFormat.string(cleanup.totalFound))
                        .font(.caption.weight(.semibold).monospacedDigit())
                }
            }

            if let top = snap.topProcesses.first {
                Divider()
                HStack {
                    Text("Top: \(top.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text(String(format: "%.1f%%", top.cpuPercent))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                Button("Open Marmot") {
                    NSApp.activate(ignoringOtherApps: true)
                    for window in NSApp.windows where !(window.title.isEmpty) {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
                Spacer()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 260)
    }

    private func row(_ icon: String, _ label: String, _ value: String,
                     _ percent: Double, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label).font(.caption)
            PercentBar(percent: percent, color: color)
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .trailing)
        }
    }

}
