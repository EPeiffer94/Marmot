import XCTest
@testable import Marmot

/// The deterministic "smart" features: ⌘K intent parsing, duplicate keeper
/// heuristics, the habit nudge, and receipt-based orphan attribution.
final class SmartFeatureTests: XCTestCase {

    // MARK: - Intent parser

    func testBigFilesIntentParsing() {
        XCTAssertEqual(IntentParser.bigFilesQuery(from: "big old videos"),
                       IntentParser.BigFilesQuery(minSizeMB: 500, minAgeDays: 180))
        XCTAssertEqual(IntentParser.bigFilesQuery(from: "files over 2gb"),
                       IntentParser.BigFilesQuery(minSizeMB: 2000, minAgeDays: 0))
        XCTAssertEqual(IntentParser.bigFilesQuery(from: "1 year old junk"),
                       IntentParser.BigFilesQuery(minSizeMB: 100, minAgeDays: 365))
        XCTAssertNil(IntentParser.bigFilesQuery(from: "cleanup"))
    }

    func testAppActionParsing() {
        XCTAssertEqual(IntentParser.appAction(from: "uninstall Slack")?.name, "slack")
        XCTAssertEqual(IntentParser.appAction(from: "uninstall Slack")?.reset, false)
        XCTAssertEqual(IntentParser.appAction(from: "reset spotify")?.reset, true)
        XCTAssertNil(IntentParser.appAction(from: "slack"))
    }

    // MARK: - Smart keeper heuristics

    private func dupe(_ path: String, daysOld: Double = 10) -> DuplicateFile {
        DuplicateFile(path: path, sizeBytes: 1_000,
                      modified: Date().addingTimeInterval(-daysOld * 86_400))
    }

    func testKeeperPrefersDocumentsOverDownloads() {
        let home = SafetyRules.home
        let docs = dupe(home + "/Documents/Taxes/report.pdf")
        let downloads = dupe(home + "/Downloads/report.pdf", daysOld: 1)
        XCTAssertEqual(DuplicateEngine.preferredKeeper(among: [downloads, docs])?.path, docs.path)
    }

    func testKeeperPenalizesCopyNames() {
        let home = SafetyRules.home
        let clean = dupe(home + "/Desktop/photo.jpg", daysOld: 30)
        let copy = dupe(home + "/Desktop/photo copy (2).jpg", daysOld: 1)
        XCTAssertEqual(DuplicateEngine.preferredKeeper(among: [copy, clean])?.path, clean.path)
    }

    func testKeeperTiebreaksByNewest() {
        let home = SafetyRules.home
        let older = dupe(home + "/Documents/a.pdf", daysOld: 30)
        let newer = dupe(home + "/Documents/b.pdf", daysOld: 1)
        XCTAssertEqual(DuplicateEngine.preferredKeeper(among: [older, newer])?.path, newer.path)
    }

    // MARK: - Habit nudge

    private func cleanupEntry(daysAgo: Double, now: Date) -> LogEntry {
        LogEntry(date: now.addingTimeInterval(-daysAgo * 86_400),
                 source: "Cleanup", dryRun: false,
                 action: ChangeAction.moveToTrash.rawValue,
                 target: "/tmp/x", sizeBytes: 1,
                 outcome: ItemOutcome.done.rawValue)
    }

    func testHabitNudgeFiresAfterThreeDays() {
        let now = Date()
        let entries = [cleanupEntry(daysAgo: 2, now: now),
                       cleanupEntry(daysAgo: 9, now: now),
                       cleanupEntry(daysAgo: 16, now: now)]
        XCTAssertNotNil(SuggestionEngine.habitNudge(entries: entries,
                                                    hasAutopilotRules: false, now: now))
        XCTAssertNil(SuggestionEngine.habitNudge(entries: entries,
                                                 hasAutopilotRules: true, now: now))
    }

    func testHabitNudgeIgnoresSingleBurstDay() {
        let now = Date()
        let entries = (0..<5).map { _ in cleanupEntry(daysAgo: 2, now: now) }
        XCTAssertNil(SuggestionEngine.habitNudge(entries: entries,
                                                 hasAutopilotRules: false, now: now))
    }

    // MARK: - Receipt family matching

    func testReceiptFamilyMatch() {
        let receipts: Set<String> = ["com.adobe.acrobat.reader", "org.videolan.vlc"]
        XCTAssertEqual(CleanupScanner.receiptFamilyMatch("com.adobe.acrobat.reader.app", in: receipts),
                       "com.adobe.acrobat.reader")
        XCTAssertEqual(CleanupScanner.receiptFamilyMatch("org.videolan", in: receipts),
                       "org.videolan.vlc")
        XCTAssertNil(CleanupScanner.receiptFamilyMatch("com.spotify.client", in: receipts))
    }
}
