import Foundation

/// One factor of the health score: what was measured, what it read, and
/// how many points it costs. Penalty 0 means healthy.
struct HealthFactor: Identifiable {
    let id: String
    let name: String
    let reading: String
    let penalty: Int
}

/// The health score WITH its receipt — Marmot shows its work here like
/// everywhere else. Pure math, no sampling: fully testable.
struct HealthReport {
    let factors: [HealthFactor]

    var score: Int {
        max(0, min(100, 100 - factors.reduce(0) { $0 + $1.penalty }))
    }

    /// The factor currently costing the most points, if any.
    var worst: HealthFactor? {
        factors.filter { $0.penalty > 0 }.max { $0.penalty < $1.penalty }
    }

    static func compute(cpuUsage: Double,
                        memoryUsedPercent: Double,
                        diskUsedPercent: Double,
                        thermal: ProcessInfo.ThermalState,
                        batteryHealth: String,
                        batteryPresent: Bool) -> HealthReport {
        var factors: [HealthFactor] = []

        factors.append(HealthFactor(
            id: "cpu", name: "CPU load",
            reading: String(format: "%.0f%%", cpuUsage),
            penalty: Int(max(0, cpuUsage - 50) * 0.5)))

        factors.append(HealthFactor(
            id: "memory", name: "Memory pressure",
            reading: String(format: "%.0f%% used", memoryUsedPercent),
            penalty: Int(max(0, memoryUsedPercent - 70) * 0.8)))

        factors.append(HealthFactor(
            id: "disk", name: "Disk space",
            reading: String(format: "%.0f%% full", diskUsedPercent),
            penalty: Int(max(0, diskUsedPercent - 80) * 1.5)))

        let thermalReading: String
        let thermalPenalty: Int
        switch thermal {
        case .nominal:
            thermalReading = "Nominal"
            thermalPenalty = 0
        case .fair:
            thermalReading = "Warm"
            thermalPenalty = 5
        case .serious:
            thermalReading = "Hot — throttling likely"
            thermalPenalty = 20
        case .critical:
            thermalReading = "Critical — heavily throttled"
            thermalPenalty = 40
        @unknown default:
            thermalReading = "—"
            thermalPenalty = 0
        }
        factors.append(HealthFactor(
            id: "thermal", name: "Thermal state",
            reading: thermalReading, penalty: thermalPenalty))

        if batteryPresent {
            let healthy = batteryHealth == "Good" || batteryHealth == "—"
            factors.append(HealthFactor(
                id: "battery", name: "Battery",
                reading: batteryHealth,
                penalty: healthy ? 0 : 5))
        }

        return HealthReport(factors: factors)
    }
}
