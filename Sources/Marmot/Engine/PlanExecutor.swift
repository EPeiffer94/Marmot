import Foundation
import AppKit

/// Executes a ChangePlan. In dry-run mode nothing is touched; every item is
/// reported as "would remove"/"would run". In real mode files go to the Trash
/// by default (recoverable), and every item is re-validated against
/// SafetyRules immediately before removal.
final class PlanExecutor {

    static func execute(_ plan: ChangePlan,
                        dryRun: Bool,
                        allowPurgeRoots: Bool = false,
                        allowUserFiles: Bool = false,
                        extraRoots: [String] = [],
                        progress: ((Double, String) -> Void)? = nil) async -> ExecutionResult {
        // Parents before children, so a nested target is recognised as
        // already handled instead of failing with "No longer exists".
        let items = TargetOverlap.executionOrder(plan.selectedItems)
        var handled = Set<String>() // file targets removed (or that would be) this run
        var results: [ItemResult] = []
        results.reserveCapacity(items.count)
        // Every result is logged the moment it exists (write-ahead), not
        // once at the end, so a crash mid-plan never loses an Undo record.
        func add(_ result: ItemResult) {
            results.append(result)
            OperationLog.shared.append(result, source: plan.source, dryRun: dryRun)
        }

        // Set when a prerequisite step (quit the app, Time Capsule archive)
        // fails: everything after it is skipped, so nothing is removed that
        // the user expected to be closed or backed up first.
        var failedPrerequisite: String?

        // A plan that came with a prerequisite step must run it. If one was
        // switched off (the preview locks them, but a plan can be built
        // anywhere), nothing after it may run.
        if let missing = plan.items.first(where: {
            PlanGroup.prerequisites.contains($0.group) && !$0.isSelected
        }) {
            add(ItemResult(item: missing, outcome: .failed,
                           detail: "This required step was turned off, so nothing else was run."))
            failedPrerequisite = missing.group
        }

        for (index, item) in items.enumerated() {
            progress?(Double(index) / Double(max(items.count, 1)), item.displayName)
            if let group = failedPrerequisite {
                add(ItemResult(item: item, outcome: .skippedAfterFailure,
                               detail: "Not run because a \"\(group)\" step failed."))
                continue
            }
            if TargetOverlap.isFileAction(item) {
                let key = TargetOverlap.key(item)
                if handled.contains(key) || TargetOverlap.hasAncestor(key, in: handled) {
                    add(ItemResult(item: item, outcome: .coveredByParent,
                                   detail: "Already included in a folder handled earlier in this plan."))
                    continue
                }
            }
            let result = await executeItem(item, dryRun: dryRun,
                                           allowPurgeRoots: allowPurgeRoots,
                                           allowUserFiles: allowUserFiles,
                                           extraRoots: extraRoots)
            add(result)
            if TargetOverlap.isFileAction(item), result.outcome == .done || result.outcome == .wouldRemove {
                handled.insert(TargetOverlap.key(item))
            }
            if !dryRun, result.outcome == .failed, PlanGroup.prerequisites.contains(item.group) {
                failedPrerequisite = item.group
            }
        }
        progress?(1.0, "Finished")

        return ExecutionResult(planTitle: plan.title, dryRun: dryRun, results: results)
    }

    private static func executeItem(_ item: ChangeItem,
                                    dryRun: Bool,
                                    allowPurgeRoots: Bool,
                                    allowUserFiles: Bool,
                                    extraRoots: [String]) async -> ItemResult {
        switch item.action {
        case .moveToTrash, .deletePermanently:
            return removeFile(item, dryRun: dryRun,
                              allowPurgeRoots: allowPurgeRoots,
                              allowUserFiles: allowUserFiles,
                              extraRoots: extraRoots)
        case .runCommand, .runAdminCommand:
            let result = runCommand(item, dryRun: dryRun)
            guard !dryRun, result.outcome == .done else { return result }
            if let bundleID = item.waitForExitOf, !(await waitForExit(bundleID: bundleID)) {
                return ItemResult(item: item, outcome: .failed,
                                  detail: "The app is still open (it may be asking to save changes). "
                                        + "Quit it yourself, then run the plan again.")
            }
            if let archive = item.verifyArchive, let problem = archiveProblem(archive) {
                return ItemResult(item: item, outcome: .failed, detail: problem)
            }
            return result
        }
    }

    /// Waits up to `timeout` seconds for every process with this bundle ID
    /// to exit. A successful quit request only means the app was asked.
    static func waitForExit(bundleID: String, timeout: TimeInterval = 15) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
                return true
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Nil when the archive exists, is non-empty, and passes `unzip -t`;
    /// otherwise a message saying why it can't be trusted as a backup.
    static func archiveProblem(_ path: String) -> String? {
        let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64 ?? 0
        guard size > 0 else { return "The Time Capsule archive wasn't created, so nothing was removed." }
        let test = Shell.run("/usr/bin/unzip", ["-tq", path], timeout: 1800)
        guard test.succeeded else {
            return "The Time Capsule archive failed its integrity check, so nothing was removed."
        }
        return nil
    }

    private static func removeFile(_ item: ChangeItem,
                                   dryRun: Bool,
                                   allowPurgeRoots: Bool,
                                   allowUserFiles: Bool,
                                   extraRoots: [String]) -> ItemResult {
        let path = item.target

        if SafetyRules.isWhitelisted(path) {
            return ItemResult(item: item, outcome: .skippedWhitelisted)
        }
        if let inner = SafetyRules.whitelistedDescendant(of: path) {
            return ItemResult(item: item, outcome: .skippedWhitelisted,
                              detail: "Contains a protected path (\(inner)), so the whole folder was left in place.")
        }
        guard SafetyRules.isSafeToRemove(path, allowPurgeRoots: allowPurgeRoots,
                                         allowUserFiles: allowUserFiles,
                                         extraRoots: extraRoots) else {
            return ItemResult(item: item, outcome: .skippedUnsafe,
                              detail: "Path failed safety validation and was not touched.")
        }
        guard FileManager.default.fileExists(atPath: path) else {
            return ItemResult(item: item, outcome: .failed, detail: "No longer exists.")
        }
        // Duplicates: the scan samples large files, so confirm the full
        // contents match the kept copy (and that it is still there) before
        // removing anything.
        if let keeper = item.verifyIdenticalTo {
            guard FileManager.default.fileExists(atPath: keeper) else {
                return ItemResult(item: item, outcome: .skippedUnsafe,
                                  detail: "The kept copy is gone, so this copy was left in place.")
            }
            guard DuplicateEngine.filesAreIdentical(path, keeper) else {
                return ItemResult(item: item, outcome: .skippedUnsafe,
                                  detail: "Not identical to the kept copy after a full check, so it was left in place.")
            }
        }
        if dryRun {
            return ItemResult(item: item, outcome: .wouldRemove)
        }

        let url = URL(fileURLWithPath: path)
        do {
            if item.action == .moveToTrash {
                var trashed: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
                return ItemResult(item: item, outcome: .done, detail: "Moved to Trash.",
                                  trashedTo: trashed?.path)
            } else {
                try FileManager.default.removeItem(at: url)
                return ItemResult(item: item, outcome: .done, detail: "Deleted.")
            }
        } catch {
            guard item.action == .moveToTrash else {
                return ItemResult(item: item, outcome: .failed, detail: error.localizedDescription)
            }

            // A permission error on an item inside the user's own home is a
            // Full Disk Access restriction — and Finder is subject to the very
            // same restriction, so asking it only produces a jarring "can't be
            // completed" modal and still fails. Skip Finder here and give the
            // one actionable instruction directly.
            if isPermissionError(error) && isUnderHome(path) {
                return ItemResult(item: item, outcome: .failed,
                                  detail: "Needs Full Disk Access. Grant it to Marmot in System Settings → "
                                        + "Privacy & Security → Full Disk Access, relaunch Marmot, and re-run.")
            }

            // Root-owned items (e.g. apps installed by a package, or files in
            // /Library) fail Marmot's direct trash but Finder can move them —
            // it shows the standard admin prompt and the item stays in Trash.
            let finder = trashViaFinder(path)
            if finder.succeeded {
                // Finder answers with the item's new home in the Trash; keep
                // it so this item can be restored like any other.
                let landed = finder.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                let trashedTo = landed.hasPrefix("/") && FileManager.default.fileExists(atPath: landed)
                    ? SafetyRules.normalize(landed) : nil
                return ItemResult(item: item, outcome: .done,
                                  detail: trashedTo == nil
                                    ? "Moved to Trash via Finder. Restore it from the Trash in Finder."
                                    : "Moved to Trash via Finder.",
                                  trashedTo: trashedTo)
            }
            let hint = finder.stderr.contains("-1743")
                ? " Allow Marmot to control Finder in System Settings → Privacy & Security → Automation, then retry."
                : (isPermissionError(error)
                    ? " This is usually Full Disk Access: grant it in System Settings → Privacy & Security, then retry."
                    : "")
            return ItemResult(item: item, outcome: .failed,
                              detail: (error.localizedDescription + hint))
        }
    }

    private static func isUnderHome(_ path: String) -> Bool {
        let home = SafetyRules.home
        return path == home || path.hasPrefix(home + "/")
    }

    /// Sandboxed-container and TCC-protected paths surface as write/permission
    /// errors — the actionable cure is almost always Full Disk Access.
    private static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain &&
            (nsError.code == NSFileWriteNoPermissionError || nsError.code == NSFileReadNoPermissionError) {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain,
           underlying.code == Int(EPERM) || underlying.code == Int(EACCES) {
            return true
        }
        return false
    }

    /// Trash an item through Finder. Finder handles privileged items by
    /// showing the standard macOS admin prompt, and the result is a normal,
    /// recoverable Trash entry. Requires the one-time Automation permission.
    private static func trashViaFinder(_ path: String) -> Shell.Output {
        let escaped = path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        // `delete` returns a reference to the item in the Trash; print its
        // POSIX path so the caller can record where it went.
        return Shell.run("/usr/bin/osascript", [
            "-e", "tell application \"Finder\"",
            "-e", "set trashedItem to delete (POSIX file \"\(escaped)\" as alias)",
            "-e", "return POSIX path of (trashedItem as alias)",
            "-e", "end tell"
        ], timeout: 120)
    }

    private static func runCommand(_ item: ChangeItem, dryRun: Bool) -> ItemResult {
        if dryRun {
            return ItemResult(item: item, outcome: .wouldRun, detail: item.target)
        }
        let output: Shell.Output
        if item.action == .runAdminCommand {
            output = Shell.runAdmin(item.target)
        } else {
            // Archiving a large app can take far longer than a normal command.
            output = Shell.runLine(item.target, timeout: item.verifyArchive != nil ? 3600 : 120)
        }
        if output.succeeded {
            return ItemResult(item: item, outcome: .done,
                              detail: output.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return ItemResult(item: item, outcome: .failed,
                          detail: output.stderr.isEmpty ? "Exit code \(output.status)" : output.stderr)
    }
}
