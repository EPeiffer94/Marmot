import XCTest
@testable import Marmot

/// The health score's receipt — factor penalties, worst-factor pick, and
/// clamping. Pure math, no sampling.
final class HealthReportTests: XCTestCase {

    private func report(cpu: Double = 10, memory: Double = 40, disk: Double = 50,
                        thermal: ProcessInfo.ThermalState = .nominal,
                        batteryHealth: String = "Good",
                        batteryPresent: Bool = true) -> HealthReport {
        HealthReport.compute(cpuUsage: cpu, memoryUsedPercent: memory,
                             diskUsedPercent: disk, thermal: thermal,
                             batteryHealth: batteryHealth,
                             batteryPresent: batteryPresent)
    }

    func testHealthyMachineScoresHundred() {
        let healthy = report()
        XCTAssertEqual(healthy.score, 100)
        XCTAssertNil(healthy.worst)
        XCTAssertTrue(healthy.factors.allSatisfy { $0.penalty == 0 })
    }

    func testMemoryPressurePenalizesAndIsWorst() {
        let pressured = report(memory: 90)
        XCTAssertEqual(pressured.score, 100 - 16) // (90-70) * 0.8
        XCTAssertEqual(pressured.worst?.id, "memory")
    }

    func testThermalStates() {
        XCTAssertEqual(report(thermal: .fair).score, 95)
        XCTAssertEqual(report(thermal: .serious).score, 80)
        XCTAssertEqual(report(thermal: .critical).score, 60)
        XCTAssertEqual(report(thermal: .serious).worst?.id, "thermal")
    }

    func testScoreClampsAtZero() {
        let dying = report(cpu: 100, memory: 100, disk: 100, thermal: .critical,
                           batteryHealth: "Service Recommended")
        XCTAssertEqual(dying.score, 0)
    }

    func testBatteryFactorOnlyWhenPresent() {
        XCTAssertTrue(report(batteryPresent: false).factors.allSatisfy { $0.id != "battery" })
        XCTAssertEqual(report(batteryHealth: "Service Recommended").score, 95)
    }

    func testDesktopWithoutBatteryStaysHealthy() {
        XCTAssertEqual(report(batteryPresent: false).score, 100)
    }
}
