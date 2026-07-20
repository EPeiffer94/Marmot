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

    // MARK: Hostile paths — the gate must fail closed on every trick

    func testHostilePathsAreRefused() {
        let hostile = [
            // Traversal variants anywhere in the path.
            home + "/Library/Caches/x/../../../Documents/taxes.pdf",
            home + "/Library/Caches/..",
            "/..",
            // Separator games. "//" collapses to "/" on disk, so a doubled
            // slash is not an escape route — but one aimed at somebody
            // else's home or at a protected area must still be refused.
            "//Users/anyone/Library/Caches/x",
            home + "//Library/Keychains/login.keychain-db",
            // Case tricks: APFS is case-insensitive but the allowlist is the
            // final gate, so a case-mangled path must simply not match it.
            home.uppercased() + "/LIBRARY/CACHES/X",
            // Whitespace and control characters.
            " ",
            "\n",
            home + "/Library/Caches/x\0y",
            // Tilde must not expand into an allowed area from a crafted string.
            "~/Library/Caches/../../Documents/x",
            // Volume roots and shallow paths.
            "/Volumes",
            "/Volumes/Backup",
            "/tmp"
        ]
        for path in hostile {
            XCTAssertFalse(SafetyRules.isSafeToRemove(path), "should refuse hostile: \(path.debugDescription)")
            XCTAssertFalse(SafetyRules.isSafeToRemove(path, allowPurgeRoots: true, allowUserFiles: true),
                           "should refuse hostile even fully unlocked: \(path.debugDescription)")
        }
    }

    func testShellQuotingNeutralizesMetacharacters() {
        // A filename crafted to escape quoting must come back inert.
        let evil = "x'; rm -rf ~; echo '$(whoami)`id`\""
        let quoted = Shell.quoted(evil)
        // Single-quoted except for escaped single quotes; no unescaped quote
        // can terminate the string early.
        XCTAssertTrue(quoted.hasPrefix("'") && quoted.hasSuffix("'"))
        XCTAssertFalse(quoted.contains("''';"))

        let script = Shell.appleScriptString("App \"Name\" \\ test")
        XCTAssertEqual(script, "\"App \\\"Name\\\" \\\\ test\"")
    }

    func testWhitelistPrefixMatchingIsExact() {
        // "/a/b" whitelisted must protect "/a/b/c" but NOT "/a/bc".
        SafetyRules.whitelist = [home + "/Library/Caches/keepme"]
        defer { SafetyRules.whitelist = [] }
        XCTAssertTrue(SafetyRules.isWhitelisted(home + "/Library/Caches/keepme/sub/file"))
        XCTAssertFalse(SafetyRules.isWhitelisted(home + "/Library/Caches/keepmeNot"))
    }
}
