import XCTest
@testable import Marmot

/// Truth table for the safety gate — the single most important code in Marmot.
final class SafetyRulesTests: XCTestCase {

    let home = SafetyRules.home

    func testSystemAndUserDataPathsAreRefused() {
        let protected = [
            "/",
            "/System/Library",
            "/usr/bin/ls",
            "/etc/hosts",
            home,
            home + "/Documents/taxes.pdf",
            home + "/Desktop/screenshot.png",
            home + "/Pictures/vacation.jpg",
            home + "/Library/Keychains/login.keychain-db",
            home + "/Library/Mail/V10/inbox",
            home + "/Library/Mobile Documents/com~apple~CloudDocs/notes.txt",
            home + "/Library/Application Support/MobileSync/Backup/phone",
            home + "/Library/Developer/Xcode/Archives/app.xcarchive"
        ]
        for path in protected {
            XCTAssertFalse(SafetyRules.isSafeToRemove(path), "should refuse: \(path)")
        }
    }

    func testKnownJunkLocationsAreAccepted() {
        let junk = [
            home + "/Library/Caches/com.foo.bar",
            home + "/Library/Logs/SomeApp/app.log",
            home + "/Library/Application Support/com.gone.app",
            home + "/.Trash/old.zip",
            home + "/Downloads/installer.dmg",
            home + "/Library/LaunchAgents/com.vendor.agent.plist"
        ]
        for path in junk {
            XCTAssertTrue(SafetyRules.isSafeToRemove(path), "should accept: \(path)")
        }
    }

    func testAllowedRootsThemselvesAreRefused() {
        XCTAssertFalse(SafetyRules.isSafeToRemove(home + "/Library/Caches"))
        XCTAssertFalse(SafetyRules.isSafeToRemove(home + "/Downloads"))
        XCTAssertFalse(SafetyRules.isSafeToRemove(home + "/.Trash"))
    }

    func testPathTraversalIsRefused() {
        XCTAssertFalse(SafetyRules.isSafeToRemove(home + "/Library/Caches/../../Documents/x"))
        XCTAssertFalse(SafetyRules.isSafeToRemove("relative/path"))
        XCTAssertFalse(SafetyRules.isSafeToRemove(""))
    }

    func testUserFilesModeUnlocksOnlyUserContent() {
        let document = home + "/Documents/duplicate.mov"
        XCTAssertFalse(SafetyRules.isSafeToRemove(document))
        XCTAssertTrue(SafetyRules.isSafeToRemove(document, allowUserFiles: true))

        // System paths stay refused even in user-files mode.
        XCTAssertFalse(SafetyRules.isSafeToRemove("/System/Library/x", allowUserFiles: true))
        XCTAssertFalse(SafetyRules.isSafeToRemove(home + "/Library/Keychains/k", allowUserFiles: true))

        // Media library packages stay refused even in user-files mode.
        let photo = home + "/Pictures/Photos Library.photoslibrary/originals/img.jpg"
        XCTAssertFalse(SafetyRules.isSafeToRemove(photo, allowUserFiles: true))
    }

    func testPurgeRootsGating() {
        let artifact = home + "/Projects/my-app/node_modules"
        XCTAssertFalse(SafetyRules.isSafeToRemove(artifact))
        XCTAssertTrue(SafetyRules.isSafeToRemove(artifact, allowPurgeRoots: true))
    }

    func testHighRiskItemsAreNeverPreselected() {
        let item = ChangeItem(target: "/tmp/x", action: .moveToTrash, risk: .high)
        let plan = ChangePlan(title: "t", source: "s", items: [item])
        XCTAssertFalse(plan.items[0].isSelected)
    }
}
