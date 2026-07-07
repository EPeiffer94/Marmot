import Foundation

/// Executes a ChangePlan. In dry-run mode nothing is touched; every item is
/// reported as "would remove"/"would run". In real mode files go to the Trash
/// by default (recoverable), and every item is re-validated against
/// SafetyRules immediately before removal.
final class PlanExecutor {

    static func execute(_ plan: ChangePlan,
                        dryRun: Bool,
                        allowPurgeRoots: Bool = false,
                        progress: ((Double, String) -> Void)? = nil) async -> ExecutionResult {
        let items = plan.selectedItems
        var results: [ItemResult] = []
        results.reserveCapacity(items.count)

        for (index, item) in items.enumerated() {
            progress?(Double(index) / Double(max(items.count, 1)), item.displayName)
            let result = await executeItem(item, dryRun: dryRun, allowPurgeRoots: allowPurgeRoots)
            results.append(result)
        }
        progress?(1.0, "Finished")

        let execution = ExecutionResult(planTitle: plan.title, dryRun: dryRun, results: results)
        OperationLog.shared.record(execution, source: plan.source)
        return execution
    }

    private static func executeItem(_ item: ChangeItem,
                                    dryRun: Bool,
                                    allowPurgeRoots: Bool) async -> ItemResult {
        switch item.action {
        case .moveToTrash, .deletePermanently:
            return removeFile(item, dryRun: dryRun, allowPurgeRoots: allowPurgeRoots)
        case .runCommand, .runAdminCommand:
            return runCommand(item, dryRun: dryRun)
        }
    }

    private static func removeFile(_ item: ChangeItem,
                                   dryRun: Bool,
                                   allowPurgeRoots: Bool) -> ItemResult {
        let path = item.target

        if SafetyRules.isWhitelisted(path) {
            return ItemResult(item: item, outcome: .skippedWhitelisted)
        }
        guard SafetyRules.isSafeToRemove(path, allowPurgeRoots: allowPurgeRoots) else {
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
                return ItemResult(item: item, outcome: .done, detail: "Moved to Trash.")
            } else {
                try FileManager.default.removeItem(at: url)
                return ItemResult(item: item, outcome: .done, detail: "Deleted.")
            }
        } catch {
            // Direct trashing fails for root-owned items (e.g. apps installed
            // by an installer package). Finder can trash those — it shows the
            // standard admin prompt itself and the item stays recoverable.
            if item.action == .moveToTrash {
                let finder = trashViaFinder(path)
                if finder.succeeded {
                    return ItemResult(item: item, outcome: .done, detail: "Moved to Trash via Finder.")
                }
                let hint = finder.stderr.contains("-1743")
                    ? " Allow Marmot to control Finder in System Settings → Privacy & Security → Automation, then retry."
                    : ""
                return ItemResult(item: item, outcome: .failed,
                                  detail: (error.localizedDescription + " Finder fallback: \(finder.stderr.trimmingCharacters(in: .whitespacesAndNewlines))" + hint))
            }
            return ItemResult(item: item, outcome: .failed, detail: error.localizedDescription)
        }
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
