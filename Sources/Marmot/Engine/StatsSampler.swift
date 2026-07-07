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
    private var previousCPUTicks: [[UInt32]] = []
    private var previousNet: (down: UInt64, up: UInt64, at: Date)?
    private var previousDiskIO: (read: UInt64, write: UInt64, at: Date)?
    private var previousProcTimes: [pid_t: UInt64] = [:]
    private var previousProcSample = Date()
    private let historyLength = 40

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

    // MARK: CPU

    private func sampleCPU() -> CPUStats {
        var stats = CPUStats()
        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)
        stats.loadAvg = (loads[0], loads[1], loads[2])

        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                         &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return stats }
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        let stateCount = Int(CPU_STATE_MAX)
        var currentTicks: [[UInt32]] = []
        var perCore: [Double] = []

        for core in 0..<Int(cpuCount) {
            let base = core * stateCount
            let user = UInt32(bitPattern: info[base + Int(CPU_STATE_USER)])
            let system = UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)])
            let nice = UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            currentTicks.append([user, system, idle, nice])

            if core < previousCPUTicks.count {
                let prev = previousCPUTicks[core]
                let dUser = Double(user &- prev[0])
                let dSystem = Double(system &- prev[1])
                let dIdle = Double(idle &- prev[2])
                let dNice = Double(nice &- prev[3])
                let total = dUser + dSystem + dIdle + dNice
                perCore.append(total > 0 ? (dUser + dSystem + dNice) / total * 100 : 0)
            } else {
                perCore.append(0)
            }
        }
        previousCPUTicks = currentTicks
        stats.perCore = perCore
        stats.totalUsage = perCore.isEmpty ? 0 : perCore.reduce(0, +) / Double(perCore.count)
        return stats
    }

    // MARK: Memory

    static func sampleMemory() -> MemoryStats {
        var stats = MemoryStats()
        stats.totalBytes = Int64(ProcessInfo.processInfo.physicalMemory)

        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return stats }
        let pageSize = Int64(vm_kernel_page_size)
        let app = Int64(vmStats.internal_page_count &- vmStats.purgeable_count) * pageSize
        let wired = Int64(vmStats.wire_count) * pageSize
        let compressed = Int64(vmStats.compressor_page_count) * pageSize
        stats.appBytes = max(app, 0)
        stats.wiredBytes = wired
        stats.compressedBytes = compressed
        stats.usedBytes = max(app, 0) + wired + compressed
        return stats
    }

    // MARK: Disk

    private func sampleDisk() -> DiskStats {
        var stats = DiskStats()
        if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys:
            [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            stats.totalBytes = Int64(values.volumeTotalCapacity ?? 0)
            stats.freeBytes = values.volumeAvailableCapacityForImportantUsage ?? 0
        }
        let io = Self.diskIOTotals()
        let now = Date()
        if let prev = previousDiskIO {
            let dt = now.timeIntervalSince(prev.at)
            if dt > 0 {
                stats.readPerSec = Double(io.read &- prev.read) / dt
                stats.writePerSec = Double(io.write &- prev.write) / dt
            }
        }
        previousDiskIO = (io.read, io.write, now)
        return stats
    }

    /// Sums bytes read/written across all IOBlockStorageDriver instances.
    static func diskIOTotals() -> (read: UInt64, write: UInt64) {
        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOBlockStorageDriver"),
                                           &iterator) == KERN_SUCCESS else {
            return (0, 0)
        }
        defer { IOObjectRelease(iterator) }
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iterator) }
            var propsRef: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = propsRef?.takeRetainedValue() as? [String: Any],
                  let statistics = props["Statistics"] as? [String: Any] else { continue }
            totalRead += (statistics["Bytes (Read)"] as? UInt64) ?? 0
            totalWrite += (statistics["Bytes (Write)"] as? UInt64) ?? 0
        }
        return (totalRead, totalWrite)
    }

    // MARK: Network

    private func sampleNetwork(previousHistory: NetworkStats) -> NetworkStats {
        var stats = NetworkStats()
        var totalDown: UInt64 = 0
        var totalUp: UInt64 = 0

        var addrsPointer: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&addrsPointer) == 0, let first = addrsPointer {
            var cursor: UnsafeMutablePointer<ifaddrs>? = first
            while let current = cursor {
                defer { cursor = current.pointee.ifa_next }
                let name = String(cString: current.pointee.ifa_name)
                guard name.hasPrefix("en") || name.hasPrefix("utun") || name.hasPrefix("pdp") else { continue }
                guard let addr = current.pointee.ifa_addr,
                      addr.pointee.sa_family == UInt8(AF_LINK),
                      let dataPtr = current.pointee.ifa_data else { continue }
                let data = dataPtr.assumingMemoryBound(to: if_data.self).pointee
                totalDown &+= UInt64(data.ifi_ibytes)
                totalUp &+= UInt64(data.ifi_obytes)
            }
            freeifaddrs(first)
        }

        let now = Date()
        if let prev = previousNet {
            let dt = now.timeIntervalSince(prev.at)
            if dt > 0 {
                stats.downPerSec = Double(totalDown &- prev.down) / dt
                stats.upPerSec = Double(totalUp &- prev.up) / dt
            }
        }
        previousNet = (totalDown, totalUp, now)

        stats.downHistory = Array((previousHistory.downHistory + [stats.downPerSec]).suffix(historyLength))
        stats.upHistory = Array((previousHistory.upHistory + [stats.upPerSec]).suffix(historyLength))
        return stats
    }

    // MARK: Battery

    static func sampleBattery() -> BatteryStats {
        var stats = BatteryStats()
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return stats
        }
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            guard (info[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            stats.present = true
            let current = (info[kIOPSCurrentCapacityKey] as? Double) ?? 0
            let maxCap = (info[kIOPSMaxCapacityKey] as? Double) ?? 100
            stats.percent = maxCap > 0 ? current / maxCap * 100 : 0
            stats.isCharging = (info[kIOPSIsChargingKey] as? Bool) ?? false
            stats.health = (info["BatteryHealth"] as? String) ?? "Normal"
        }
        return stats
    }

    // MARK: GPU (best effort)

    static func sampleGPU() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOAccelerator"),
                                           &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iterator) }
            var propsRef: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = propsRef?.takeRetainedValue() as? [String: Any],
                  let perf = props["PerformanceStatistics"] as? [String: Any] else { continue }
            if let utilization = perf["Device Utilization %"] as? Int {
                return Double(utilization)
            }
            if let utilization = perf["GPU Activity(%)"] as? Int {
                return Double(utilization)
            }
        }
        return nil
    }

    // MARK: Processes (libproc — no process spawning)

    private func sampleProcesses() -> [ProcessStat] {
        let now = Date()
        let wall = now.timeIntervalSince(previousProcSample)
        previousProcSample = now

        var pidCount = proc_listallpids(nil, 0)
        guard pidCount > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(pidCount) + 32)
        pidCount = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard pidCount > 0 else { return [] }

        var current: [pid_t: UInt64] = [:]
        var stats: [ProcessStat] = []
        for pid in pids.prefix(Int(pidCount)) where pid > 0 {
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.stride)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { continue }
            let total = info.pti_total_user &+ info.pti_total_system
            current[pid] = total
            guard wall > 0, let previous = previousProcTimes[pid], total >= previous else { continue }
            let percent = Double(total - previous) / 1_000_000_000.0 / wall * 100.0
            guard percent >= 0.1 else { continue }
            var nameBuffer = [CChar](repeating: 0, count: 256)
            proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let name = String(cString: nameBuffer)
            stats.append(ProcessStat(id: Int(pid),
                                     name: name.isEmpty ? "pid \(pid)" : name,
                                     cpuPercent: percent))
        }
        previousProcTimes = current
        return Array(stats.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(6))
    }

    // MARK: Misc

    static func uptimeString() -> String {
        let uptime = ProcessInfo.processInfo.systemUptime
        let days = Int(uptime) / 86400
        let hours = (Int(uptime) % 86400) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        return "\(hours)h \(minutes)m"
    }

    static func healthScore(_ snap: SystemSnapshot) -> Int {
        var score = 100.0
        score -= max(0, snap.cpu.totalUsage - 50) * 0.5       // heavy CPU
        score -= max(0, snap.memory.usedPercent - 70) * 0.8   // memory pressure
        let diskUsed = snap.disk.usedPercent
        score -= max(0, diskUsed - 80) * 1.5                  // nearly-full disk
        return max(0, min(100, Int(score)))
    }
}
