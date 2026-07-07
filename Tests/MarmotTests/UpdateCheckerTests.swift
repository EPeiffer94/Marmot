import XCTest
@testable import Marmot

final class UpdateCheckerTests: XCTestCase {

    func testVersionComparison() {
        XCTAssertTrue(UpdateChecker.isNewer("1.2.0", than: "1.1.9"))
        XCTAssertTrue(UpdateChecker.isNewer("2.0", than: "1.9.9"))
        XCTAssertTrue(UpdateChecker.isNewer("1.10", than: "1.9"))
        XCTAssertTrue(UpdateChecker.isNewer("1.0.1", than: "1.0"))

        XCTAssertFalse(UpdateChecker.isNewer("1.0.0", than: "1.0.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0", than: "1.0.1"))
        XCTAssertFalse(UpdateChecker.isNewer("0.9", than: "1.0"))

        // Non-numeric versions never count as newer.
        XCTAssertFalse(UpdateChecker.isNewer("latest", than: "1.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0", than: "latest"))
    }

    func testVersionsWithPrefixesAndSuffixes() {
        XCTAssertTrue(UpdateChecker.isNewer("v2.1", than: "v2.0.5"))
        XCTAssertTrue(UpdateChecker.isNewer("3.0-beta.2", than: "3.0-beta.1"))
    }
}
