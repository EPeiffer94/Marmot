import XCTest
@testable import Marmot

/// Background automation: Autopilot's schedule math and the Startup
/// Sentinel's new-arrival diffing.
final class AutopilotAndSentinelTests: XCTestCase {

    // MARK: - Autopilot scheduling

    func testNewRuleIsNotDueImmediately() {
        let rule = AutopilotRule(name: "r", categoryIDs: ["logs"],
                                 frequency: .weekly, createdAt: Date())
        XCTAssertFalse(rule.isDue(at: Date()))
        XCTAssertTrue(rule.isDue(at: Date().addingTimeInterval(8 * 86_400)))
    }

    func testRuleDueAfterInterval() {
        var rule = AutopilotRule(name: "r", categoryIDs: ["logs"], frequency: .daily)
        rule.lastRun = Date().addingTimeInterval(-2 * 86_400)
        XCTAssertTrue(rule.isDue(at: Date()))
        rule.isEnabled = false
        XCTAssertFalse(rule.isDue(at: Date()))
    }

    // MARK: - Startup Sentinel diffing

    func testSentinelNewArrivals() {
        let known = ["/L/A/com.known.one.plist", "/L/A/com.known.two.plist"]
        let current = ["/L/A/com.known.one.plist", "/L/A/com.sneaky.new.plist"]
        XCTAssertEqual(StartupSentinel.newArrivals(current: current, known: known),
                       ["/L/A/com.sneaky.new.plist"])
        // Nothing new → empty. Removed items are not "arrivals".
        XCTAssertTrue(StartupSentinel.newArrivals(current: known, known: known).isEmpty)
        XCTAssertTrue(StartupSentinel.newArrivals(current: [], known: known).isEmpty)
        // Everything is new against an empty baseline.
        XCTAssertEqual(StartupSentinel.newArrivals(current: current, known: []).count, 2)
    }
}
