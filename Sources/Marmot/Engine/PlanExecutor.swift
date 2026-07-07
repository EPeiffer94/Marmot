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
            // Trash can fail for items on other volumes; fall back to delete
            // only if the user chose permanent deletion. Otherwise report.
            return ItemResult(item: item, outcome: .failed, detail: error.localizedDescription)
        }
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
