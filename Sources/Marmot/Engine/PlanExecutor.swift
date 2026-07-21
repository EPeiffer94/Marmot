import Foundation

/// Executes a ChangePlan. In dry-run mode nothing is touched; every item is
/// reported as "would remove"/"would run". In real mode files go to the Trash
/// by default (recoverable), and every item is re-validated against
/// SafetyRules immediately before removal.
final class PlanExecutor {

    static func execute(_ plan: ChangePlan,
                        dryRun: Bool,
                        allowPurgeRoots: Bool = false,
                        allowUserFiles: Bool = false,
                        progress: ((Double, String) -> Void)? = nil) async -> ExecutionResult {
        let items = plan.selectedItems
        var results: [ItemResult] = []
        results.reserveCapacity(items.count)

        for (index, item) in items.enumerated() {
            progress?(Double(index) / Double(max(items.count, 1)), item.displayName)
            let result = await executeItem(item, dryRun: dryRun,
                                           allowPurgeRoots: allowPurgeRoots,
                                           allowUserFiles: allowUserFiles)
            results.append(result)
        }
        progress?(1.0, "Finished")

        let execution = ExecutionResult(planTitle: plan.title, dryRun: dryRun, results: results)
        OperationLog.shared.record(execution, source: plan.source)
        return execution
    }

    private static func executeItem(_ item: ChangeItem,
                                    dryRun: Bool,
                                    allowPurgeRoots: Bool,
                                    allowUserFiles: Bool) async -> ItemResult {
        switch item.action {
        case .moveToTrash, .deletePermanently:
            return removeFile(item, dryRun: dryRun,
                              allowPurgeRoots: allowPurgeRoots,
                              allowUserFiles: allowUserFiles)
        case .runCommand, .runAdminCommand:
            return runCommand(item, dryRun: dryRun)
        }
    }

    private static func removeFile(_ item: ChangeItem,
                                   dryRun: Bool,
                                   allowPurgeRoots: Bool,
                                   allowUserFiles: Bool) -> ItemResult {
        let path = item.target

        if SafetyRules.isWhitelisted(path) {
            return ItemResult(item: item, outcome: .skippedWhitelisted)
        }
        guard SafetyRules.isSafeToRemove(path, allowPurgeRoots: allowPurgeRoots,
                                         allowUserFiles: allowUserFiles) else {
            return ItemResult(item: item, outcome: .skippedUnsafe,
                              detail: "Path failed safety validation and was not touched.")
        }
        guard FileManager.default.fileExists(atPath: path) else {
            return ItemResult(item: item, outcome: .failed, detail: "No longer exists.")
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
                return ItemResult(item: item, outcome: .done, detail: "Moved to Trash via Finder.")
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
        let script = "tell application \"Finder\" to delete (POSIX file \"\(escaped)\" as alias)"
        return Shell.run("/usr/bin/osascript", ["-e", script], timeout: 120)
    }

    private static func runCommand(_ item: ChangeItem, dryRun: Bool) -> ItemResult {
        if dryRun {
            return ItemResult(item: item, outcome: .wouldRun, detail: item.target)
        }
        let output: Shell.Output
        if item.action == .runAdminCommand {
            output = Shell.runAdmin(item.target)
        } else {
            output = Shell.runLine(item.target)
        }
        if output.succeeded {
            return ItemResult(item: item, outcome: .done,
                              detail: output.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return ItemResult(item: item, outcome: .failed,
                          detail: output.stderr.isEmpty ? "Exit code \(output.status)" : output.stderr)
    }
}
