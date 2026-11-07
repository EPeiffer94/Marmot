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

    // MARK: Appcast parsing

    private func latest(_ items: String) -> String? {
        let feed = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>\(items)</channel>
        </rss>
        """
        return SparkleAppcastParser.latestVersion(in: Data(feed.utf8))
    }

    /// Regression: versions written as child elements (the modern format,
    /// and Marmot's own feed) were never read.
    func testAppcastWithVersionElements() {
        let items = """
        <item>
          <sparkle:version>132</sparkle:version>
          <sparkle:shortVersionString>4.0.0</sparkle:shortVersionString>
          <enclosure url="https://example.com/a.zip" length="1" type="application/octet-stream" />
        </item>
        <item>
          <sparkle:version>125</sparkle:version>
          <sparkle:shortVersionString>3.2.0</sparkle:shortVersionString>
          <enclosure url="https://example.com/b.zip" length="1" type="application/octet-stream" />
        </item>
        """
        XCTAssertEqual(latest(items), "4.0.0")
    }

    func testAppcastWithEnclosureAttributes() {
        let items = """
        <item><enclosure url="https://example.com/a.zip" sparkle:version="210" sparkle:shortVersionString="2.1" /></item>
        <item><enclosure url="https://example.com/b.zip" sparkle:version="200" sparkle:shortVersionString="2.0" /></item>
        """
        XCTAssertEqual(latest(items), "2.1")
    }

    /// A bare build number can't be compared with a marketing version.
    func testBuildNumberOnlyIsIgnored() {
        XCTAssertNil(latest(#"<item><enclosure url="https://example.com/a.zip" sparkle:version="132" /></item>"#))
        XCTAssertEqual(latest(#"<item><enclosure url="https://example.com/a.zip" sparkle:version="1.4.2" /></item>"#),
                       "1.4.2")
    }

    func testBetaChannelsAndUnsupportedOSAreIgnored() {
        let items = """
        <item>
          <sparkle:channel>beta</sparkle:channel>
          <sparkle:shortVersionString>9.0.0</sparkle:shortVersionString>
        </item>
        <item>
          <sparkle:minimumSystemVersion>99.0</sparkle:minimumSystemVersion>
          <sparkle:shortVersionString>8.0.0</sparkle:shortVersionString>
        </item>
        <item>
          <sparkle:shortVersionString>5.0.0</sparkle:shortVersionString>
        </item>
        """
        XCTAssertEqual(latest(items), "5.0.0")
    }
}
