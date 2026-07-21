import XCTest
@testable import Marmot

/// Storage-trend analytics: the disk-full forecast and the freed-space
/// aggregation behind the Dashboard report card.
final class TrendAndLogTests: XCTestCase {

    // MARK: - Space forecast

    private func point(day: Int, used: Int64, free: Int64) -> TrendPoint {
        TrendPoint(date: Date(timeIntervalSince1970: Double(day) * 86_400),
                   diskTotal: used + free, diskFree: free,
                   junkTotal: 0, categorySizes: [:])
    }

    func testForecastRisingUsage() {
        // +10 GB/day, 100 GB free at the end → ~10 days.
        let points = (0..<10).map {
            point(day: $0, used: Int64($0 + 1) * 10_000_000_000, free: 100_000_000_000)
        }
        let days = TrendStore.daysUntilFull(points: points)
        XCTAssertNotNil(days)
        XCTAssertTrue((8...12).contains(days ?? 0), "expected ~10 days, got \(String(describing: days))")
    }

    func testForecastFlatUsageReturnsNil() {
        let points = (0..<10).map { point(day: $0, used: 500_000_000_000, free: 100_000_000_000) }
        XCTAssertNil(TrendStore.daysUntilFull(points: points))
    }

    func testForecastNeedsEnoughSignal() {
        let few = (0..<3).map { point(day: $0, used: Int64($0) * 10_000_000_000, free: 1_000_000_000_000) }
        XCTAssertNil(TrendStore.daysUntilFull(points: few))
        let narrow = (0..<6).map { point(day: 0, used: Int64($0) * 10_000_000_000, free: 1_000_000_000_000) }
        XCTAssertNil(TrendStore.daysUntilFull(points: narrow)) // all same day
    }

    // MARK: - Freed-space aggregation

    private func entry(daysAgo: Double, bytes: Int64, now: Date,
                       dryRun: Bool = false,
                       action: String = ChangeAction.moveToTrash.rawValue,
                       outcome: String = ItemOutcome.done.rawValue) -> LogEntry {
        LogEntry(date: now.addingTimeInterval(-daysAgo * 86_400),
                 source: "Test", dryRun: dryRun, action: action,
                 target: "/tmp/x", sizeBytes: bytes, outcome: outcome)
    }

    func testFreedStatsWindowsAndFilters() {
        let now = Date()
        let stats = OperationLog.aggregate([
            entry(daysAgo: 1, bytes: 100, now: now),                       // week + month + all
            entry(daysAgo: 10, bytes: 1_000, now: now),                    // month + all
            entry(daysAgo: 100, bytes: 10_000, now: now),                  // all only
            entry(daysAgo: 1, bytes: 999_999, now: now, dryRun: true),     // ignored
            entry(daysAgo: 1, bytes: 999_999, now: now,
                  outcome: ItemOutcome.failed.rawValue)                     // ignored
        ], now: now)
        XCTAssertEqual(stats.last7Days, 100)
        XCTAssertEqual(stats.last30Days, 1_100)
        XCTAssertEqual(stats.allTime, 11_100)
        XCTAssertEqual(stats.biggestRecent?.sizeBytes, 1_000)
    }
}
