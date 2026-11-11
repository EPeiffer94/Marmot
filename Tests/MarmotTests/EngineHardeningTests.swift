import XCTest
@testable import Marmot

/// Regression tests for the Nov 2026 engine review: protected children,
/// path hardening, prerequisites, Autopilot limits, overlapping targets,
/// fts post-order handling, full-hash duplicates, and honest byte counts.
final class EngineHardeningTests: XCTestCase {

    private var directory: URL!
    private var root: String { directory.path }
    private var savedWhitelist: [String] = []
    private var savedLogURL: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("marmot-hardening-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        savedWhitelist = SafetyRules.whitelist
        SafetyRules.whitelist = []
        // Executor runs write History entries: keep them out of the real log.
        savedLogURL = OperationLog.shared.fileURL
        OperationLog.shared.fileURL = directory.appendingPathComponent("test-log.jsonl")
    }

    override func tearDownWithError() throws {
        SafetyRules.whitelist = savedWhitelist
        OperationLog.shared.fileURL = savedLogURL
        // The fts test locks a folder; unlock it so cleanup can recurse.
        try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                               ofItemAtPath: root + "/tree/locked")
        try? FileManager.default.removeItem(at: directory)
    }

    @discardableResult
    private func makeDir(_ rel: String) throws -> String {
        let path = root + "/" + rel
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    @discardableResult
    private func makeFile(_ rel: String, _ data: Data = Data([1, 2, 3])) throws -> String {
        let path = root + "/" + rel
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: path))
        return path
    }

    private func trashItem(_ path: String, size: Int64 = 10, selected: Bool = true,
                           group: String = "Test", risk: RiskLevel = .low) -> ChangeItem {
        ChangeItem(target: path, action: .moveToTrash, sizeBytes: size, risk: risk,
                   group: group, isSelected: selected)
    }

    // MARK: - 1. Whitelisted children

    func testWhitelistedDescendantIsFound() {
        let home = SafetyRules.home
        SafetyRules.whitelist = [home + "/Library/Caches/Google/Chrome"]
        XCTAssertEqual(SafetyRules.whitelistedDescendant(of: home + "/Library/Caches/Google"),
                       home + "/Library/Caches/Google/Chrome")
        // Prefix trap: "Goo" is not a parent of "Google/Chrome".
        XCTAssertNil(SafetyRules.whitelistedDescendant(of: home + "/Library/Caches/Goo"))
        XCTAssertNil(SafetyRules.whitelistedDescendant(of: home + "/Library/Caches/Other"))
        // The whitelisted path itself is "whitelisted", not a descendant.
        XCTAssertNil(SafetyRules.whitelistedDescendant(of: home + "/Library/Caches/Google/Chrome"))
        XCTAssertTrue(SafetyRules.isWhitelisted(home + "/Library/Caches/Google/Chrome/Cache"))
    }

    func testExecutorSkipsParentOfWhitelistedPath() async throws {
        let parent = try makeDir("Google")
        let child = try makeDir("Google/Chrome")
        try makeDir("Other")
        SafetyRules.whitelist = [child]
        let plan = ChangePlan(title: "t", source: "Test",
                              items: [trashItem(parent), trashItem(root + "/Other")])
        let result = await PlanExecutor.execute(plan, dryRun: true, extraRoots: [root])
        XCTAssertEqual(result.results.first { $0.item.target == parent }?.outcome, .skippedWhitelisted)
        XCTAssertEqual(result.results.first { $0.item.target == root + "/Other" }?.outcome, .wouldRemove)
    }

    // MARK: - C. Path hardening

    func testFoldersContainingProtectedAreasAreRefused() {
        let home = SafetyRules.home
        XCTAssertFalse(SafetyRules.isSafeToRemove(home + "/Library/Developer/Xcode"))
        XCTAssertTrue(SafetyRules.isSafeToRemove(home + "/Library/Developer/Xcode/DerivedData/App-abc"))
    }

    func testComparisonsIgnoreCase() {
        let home = SafetyRules.home
        XCTAssertFalse(SafetyRules.isSafeToRemove(home + "/documents/taxes.pdf"))
        XCTAssertFalse(SafetyRules.isAcceptableExtraRoot(home + "/library/Foo"))
        XCTAssertFalse(SafetyRules.isAcceptableExtraRoot("/system/Library"))
        let pick = SafetyRules.home + "/Pictures/Holiday"
        XCTAssertTrue(SafetyRules.isAcceptableExtraRoot(pick))
    }

    func testSymlinkedFolderBelowRootIsRefused() throws {
        let outside = try makeDir("outside")
        try makeFile("outside/secret.txt")
        let picked = try makeDir("picked")
        try makeDir("picked/real")
        try FileManager.default.createSymbolicLink(atPath: picked + "/link", withDestinationPath: outside)

        XCTAssertFalse(SafetyRules.isSafeToRemove(picked + "/link/secret.txt", extraRoots: [picked]),
                       "a path through a symlinked folder must be refused")
        XCTAssertTrue(SafetyRules.isSafeToRemove(picked + "/link", extraRoots: [picked]),
                      "the link itself may go: trashing a link removes only the link")
        XCTAssertTrue(SafetyRules.isSafeToRemove(picked + "/real/file", extraRoots: [picked]))
    }

    // MARK: - 2. Prerequisites

    func testDeselectedPrerequisiteBlocksThePlan() async throws {
        let file = try makeFile("app-data.bin")
        var quit = ChangeItem(target: "true", action: .runCommand, group: PlanGroup.beforeStarting)
        quit.isSelected = false
        let plan = ChangePlan(title: "t", source: "Test", items: [quit, trashItem(file)])
        let result = await PlanExecutor.execute(plan, dryRun: true, extraRoots: [root])
        XCTAssertEqual(result.results.first?.outcome, .failed)
        XCTAssertEqual(result.results.last?.outcome, .skippedAfterFailure)
    }

    func testArchiveCheck() throws {
        XCTAssertNotNil(PlanExecutor.archiveProblem(root + "/missing.zip"))
        let bogus = try makeFile("bogus.zip", Data("not a zip".utf8))
        XCTAssertNotNil(PlanExecutor.archiveProblem(bogus))
        try makeFile("payload/a.txt", Data("hello".utf8))
        let zip = root + "/good.zip"
        let made = Shell.run("/usr/bin/zip", ["-qry", zip, root + "/payload"])
        XCTAssertTrue(made.succeeded)
        XCTAssertNil(PlanExecutor.archiveProblem(zip))
    }

    // MARK: - A, B. Autopilot

    func testAutopilotEligibility() {
        let now = Date()
        XCTAssertTrue(Autopilot.isEligibleUnattended(trashItem("/x"), addedToTrash: nil, now: now))
        XCTAssertFalse(Autopilot.isEligibleUnattended(trashItem("/x", risk: .medium), addedToTrash: nil, now: now))
        XCTAssertFalse(Autopilot.isEligibleUnattended(trashItem("/x", selected: false), addedToTrash: nil, now: now))

        let trash = ChangeItem(target: "/t", action: .deletePermanently, risk: .medium, group: "Trash")
        XCTAssertFalse(Autopilot.isEligibleUnattended(trash, addedToTrash: nil, now: now))
        XCTAssertFalse(Autopilot.isEligibleUnattended(trash, addedToTrash: now.addingTimeInterval(-86_400), now: now))
        XCTAssertTrue(Autopilot.isEligibleUnattended(trash, addedToTrash: now.addingTimeInterval(-8 * 86_400), now: now))
    }

    // MARK: - 4. Overlapping targets

    func testUniqueSizeCountsNestedAndRepeatedTargetsOnce() {
        let items = [trashItem("/a/Caches/Google", size: 100),
                     trashItem("/a/Caches/Google/Chrome", size: 40),
                     trashItem("/a/Caches/Google", size: 100),
                     trashItem("/a/Caches/GoogleUpdater", size: 7),
                     trashItem("/a/Caches/Other", size: 10)]
        XCTAssertEqual(TargetOverlap.uniqueSize(of: items), 117)
    }

    func testExecutionOrderPutsParentsFirstAndKeepsCommandsInPlace() {
        let cmd = ChangeItem(target: "true", action: .runCommand, group: PlanGroup.beforeStarting)
        let ordered = TargetOverlap.executionOrder([cmd, trashItem("/a/b/c"), trashItem("/a/b")])
        XCTAssertEqual(ordered.map(\.target), ["true", "/a/b", "/a/b/c"])
    }

    func testExecutorMarksNestedAndRepeatedItemsAsCovered() async throws {
        let parent = try makeDir("Caches/Google")
        let child = try makeDir("Caches/Google/Chrome")
        let plan = ChangePlan(title: "t", source: "Test",
                              items: [trashItem(child), trashItem(parent), trashItem(parent)])
        let result = await PlanExecutor.execute(plan, dryRun: true, extraRoots: [root])
        XCTAssertEqual(result.results.map(\.outcome), [.wouldRemove, .coveredByParent, .coveredByParent])
        XCTAssertEqual(result.results.first?.item.target, parent)
    }

    // MARK: - 5. fts post-order contract

    func testWalkerClosesEveryEnteredFolderExactlyOnce() throws {
        try makeFile("tree/a/f")
        try makeFile("tree/skipme/x/f")
        try makeFile("tree/locked/inner/f")
        try makeFile("tree/z/f")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: root + "/tree/locked")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root + "/tree/locked")
        }

        var stack: [String] = []
        var mismatches: [String] = []
        var posted: [String] = []
        FTSWalker.walk(
            root: root + "/tree",
            directoryPre: { path, _, _ in
                if path.hasSuffix("/skipme") { return .skip }
                stack.append(path)
                return .descend
            },
            directoryPost: { path, _ in
                posted.append(path)
                if stack.popLast() != path { mismatches.append(path) }
            },
            file: { _, _, _ in })

        XCTAssertTrue(mismatches.isEmpty, "post-order visits out of step: \(mismatches)")
        XCTAssertTrue(stack.isEmpty, "folders never closed: \(stack)")
        XCTAssertFalse(posted.contains { $0.hasSuffix("/skipme") }, "skipped folders must not be closed")
        XCTAssertTrue(posted.contains { $0.hasSuffix("/locked") }, "unreadable folders must still be closed")
    }

    // MARK: - 6. Full-hash duplicates

    func testSampledLookalikesAreNotReportedAsDuplicates() throws {
        let size = 6 * 1024 * 1024
        let original = Data(repeating: 0, count: size)
        var changed = original
        changed[1_500_000] = 1 // between the head and middle samples
        try makeFile("dups/a.img", original)
        try makeFile("dups/b.img", changed)
        try makeFile("dups/c.img", original)

        let groups = DuplicateEngine().scan(roots: [root + "/dups"])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].files.map(\.name)), ["a.img", "c.img"])
    }

    // MARK: - 7. Honest byte counts

    func testTrashAndDeleteAreReportedSeparately() {
        let trashed = ItemResult(item: trashItem("/a", size: 100), outcome: .done, trashedTo: "/t/a")
        let deleted = ItemResult(item: ChangeItem(target: "/b", action: .deletePermanently, sizeBytes: 30),
                                 outcome: .done)
        let failed = ItemResult(item: trashItem("/c", size: 500), outcome: .failed)
        let result = ExecutionResult(planTitle: "t", dryRun: false, results: [trashed, deleted, failed])
        XCTAssertEqual(result.trashedBytes, 100)
        XCTAssertEqual(result.deletedBytes, 30)
        XCTAssertEqual(result.removedBytes, 130)
    }

    func testEmptyingTrashIsNotCountedTwice() {
        let home = SafetyRules.home
        func entry(_ action: ChangeAction, _ target: String, _ size: Int64, trashedTo: String? = nil) -> LogEntry {
            LogEntry(date: Date(), source: "Cleanup", dryRun: false, action: action.rawValue,
                     target: target, sizeBytes: size, outcome: ItemOutcome.done.rawValue,
                     trashedTo: trashedTo)
        }
        let entries = [
            entry(.moveToTrash, home + "/Library/Caches/big", 100, trashedTo: home + "/.Trash/big"),
            entry(.deletePermanently, home + "/.Trash/big", 100),      // Marmot's own: already counted
            entry(.deletePermanently, home + "/.Trash/user-file", 50)  // trashed in Finder: new
        ]
        XCTAssertEqual(OperationLog.countedRemovals(entries).reduce(0) { $0 + $1.sizeBytes }, 150)
        XCTAssertEqual(OperationLog.aggregate(entries).allTime, 150)
    }

    // MARK: - E. Build-artifact markers

    func testArtifactMarkers() throws {
        XCTAssertTrue(CleanupScanner.hasArtifactMarker(name: "node_modules", artifact: "/p/node_modules",
                                                       siblings: ["package.json", "src"]))
        XCTAssertFalse(CleanupScanner.hasArtifactMarker(name: "build", artifact: "/p/build",
                                                        siblings: ["build", "README.md"]))
        XCTAssertTrue(CleanupScanner.hasArtifactMarker(name: "build", artifact: "/p/build",
                                                       siblings: ["build", "App.xcodeproj"]))
        XCTAssertTrue(CleanupScanner.hasArtifactMarker(name: "target", artifact: "/p/target",
                                                       siblings: ["Cargo.toml"]))
        let venv = try makeDir("proj/.venv")
        XCTAssertFalse(CleanupScanner.hasArtifactMarker(name: ".venv", artifact: venv, siblings: []))
        try makeFile("proj/.venv/pyvenv.cfg")
        XCTAssertTrue(CleanupScanner.hasArtifactMarker(name: ".venv", artifact: venv, siblings: []))
    }
}
