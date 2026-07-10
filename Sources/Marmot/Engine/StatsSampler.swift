import Foundation
import IOKit
import IOKit.ps
import Darwin

struct CPUStats {
    var totalUsage: Double = 0            // 0...100
    var perCore: [Double] = []
    var loadAvg: (Double, Double, Double) = (0, 0, 0)
}

struct MemoryStats {
    var totalBytes: Int64 = 0
    var usedBytes: Int64 = 0
    var appBytes: Int64 = 0
    var wiredBytes: Int64 = 0
    var compressedBytes: Int64 = 0
    var usedPercent: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) * 100 : 0 }
}

struct DiskStats {
    var totalBytes: Int64 = 0
    var freeBytes: Int64 = 0
    var readPerSec: Double = 0
    var writePerSec: Double = 0
    var usedPercent: Double {
        totalBytes > 0 ? Double(totalBytes - freeBytes) / Double(totalBytes) * 100 : 0
    }
}

struct NetworkStats {
    var downPerSec: Double = 0
    var upPerSec: Double = 0
    var downHistory: [Double] = []
    var upHistory: [Double] = []
}

struct BatteryStats {
    var present = false
    var percent: Double = 0
    var isCharging = false
    var health: String = "—"
    var cycleCount: Int = 0
}

struct ProcessStat: Identifiable {
    let id: Int
    let name: String
    let cpuPercent: Double
}

struct SystemSnapshot {
    var cpu = CPUStats()
    var memory = MemoryStats()
    var disk = DiskStats()
    var network = NetworkStats()
    var battery = BatteryStats()
    var gpuUsage: Double? = nil
    var topProcesses: [ProcessStat] = []
    var uptime: String = ""
    var healthScore: Int = 100
}

/// Samples live system statistics roughly every 2 seconds.
/// The individual samplers live in StatsSampler+Samplers.swift.
///
/// Held as a shared singleton — deliberately NOT owned by the App struct via
/// @StateObject. If the App body observed this object, every 2-second sample
/// would re-evaluate all scenes and trigger a main-menu rebuild storm that
/// pegs the main thread. Only leaf views observe it.
final class StatsSampler: ObservableObject {

    static let shared = StatsSampler()

    @Published var snapshot = SystemSnapshot()

    private var timer: Timer?
    /// All mutable sampling state is confined to this serial queue.
    private let sampleQueue = DispatchQueue(label: "marmot.stats", qos: .utility)

    // Sampler working state (internal so the samplers extension can use it).
    var previousCPUTicks: [[UInt32]] = []
    var previousNet: (down: UInt64, up: UInt64, at: Date)?
    var previousDiskIO: (read: UInt64, write: UInt64, at: Date)?
    var previousProcTimes: [pid_t: UInt64] = [:]
    var previousProcSample = Date()
    let historyLength = 40

    func start() {
        stop()
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.sample()
        }
        timer.map { RunLoop.main.add($0, forMode: .common) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        sampleQueue.async { [weak self] in
            guard let self else { return }
            var snap = SystemSnapshot()
            snap.cpu = self.sampleCPU()
            snap.memory = Self.sampleMemory()
            snap.disk = self.sampleDisk()
            snap.network = self.sampleNetwork(previousHistory: self.snapshot.network)
            snap.battery = Self.sampleBattery()
            snap.gpuUsage = Self.sampleGPU()
            snap.topProcesses = self.sampleProcesses()
            snap.uptime = Self.uptimeString()
            snap.healthScore = Self.healthScore(snap)
            DispatchQueue.main.async {
                self.snapshot = snap
            }
        }
    }
}
