import Foundation

// MARK: - The core idea of Marmot
// Nothing destructive ever happens directly. Every operation first produces a
// ChangePlan — a full, inspectable list of what WOULD happen. The user reviews
// it visually, can toggle items off, run it as a dry run, and only then apply.

enum ChangeAction: String, Codable, CaseIterable {
    case moveToTrash = "Move to Trash"
    case deletePermanently = "Delete permanently"
    case runCommand = "Run command"
    case runAdminCommand = "Run command (admin)"
}

enum RiskLevel: Int, Codable, Comparable {
    case low = 0
    case medium = 1
    case high = 2

    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

struct ChangeItem: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    /// Filesystem path for file actions, or the shell command for command actions.
    let target: String
    let action: ChangeAction
    var sizeBytes: Int64 = 0
    var risk: RiskLevel = .low
    /// Human explanation of what this is and why it is safe (or not) to remove.
    var note: String = ""
    /// Group label used by the preview UI (e.g. "Caches", "Launch Agents").
    var group: String = "General"
    var isSelected: Bool = true
    /// Duplicates only: the kept copy. Right before removal the executor
    /// checks it still exists and is byte-for-byte identical; otherwise this
    /// item is left untouched.
    var verifyIdenticalTo: String? = nil
    /// Quit steps only: the bundle ID that must actually stop running. A
    /// quit request can succeed while the app stays open (a "Save changes?"
    /// sheet), so the executor waits for the process to exit.
    var waitForExitOf: String? = nil
    /// Archive steps only: the zip the command writes. The executor tests
    /// it after the command, so "succeeded" means "restorable".
    var verifyArchive: String? = nil

    var displayName: String {
        if action == .runCommand || action == .runAdminCommand { return target }
        return (target as NSString).lastPathComponent
    }
}

struct ChangePlan: Identifiable, Sendable {
    let id = UUID()
    let title: String
    /// Where this plan came from, e.g. "Cleanup", "Uninstall Photoshop".
    let source: String
    var items: [ChangeItem]
    let createdAt = Date()

    init(title: String, source: String, items: [ChangeItem]) {
        self.title = title
        self.source = source
        // High-risk items are never pre-selected, no matter who built them.
        self.items = items.map {
            var item = $0
            if item.risk == .high { item.isSelected = false }
            return item
        }
    }

    var selectedItems: [ChangeItem] { items.filter { $0.isSelected } }
    /// Nested and repeated targets are counted once (see TargetOverlap).
    var selectedSize: Int64 { TargetOverlap.uniqueSize(of: selectedItems) }
    var totalSize: Int64 { TargetOverlap.uniqueSize(of: items) }
    var groups: [String] {
        var seen = Set<String>()
        return items.compactMap { seen.insert($0.group).inserted ? $0.group : nil }
    }
    var highestRisk: RiskLevel { items.map(\.risk).max() ?? .low }

    /// Plain-language summary shown before applying.
    var summary: String {
        let files = selectedItems.filter { $0.action == .moveToTrash || $0.action == .deletePermanently }
        let cmds = selectedItems.filter { $0.action == .runCommand || $0.action == .runAdminCommand }
        var parts: [String] = []
        if !files.isEmpty {
            parts.append("\(files.count) item\(files.count == 1 ? "" : "s") (\(ByteFormat.string(selectedSize))) across \(Set(files.map(\.group)).count) location group\(Set(files.map(\.group)).count == 1 ? "" : "s")")
        }
        if !cmds.isEmpty {
            parts.append("\(cmds.count) command\(cmds.count == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "Nothing selected" : parts.joined(separator: " and ")
    }
}

/// Plan groups whose steps must succeed before anything else runs (quitting
/// the app, archiving it to a Time Capsule). If one fails, PlanExecutor skips
/// the rest of the plan rather than removing files the user expected to be
/// backed up or closed first.
enum PlanGroup {
    static let beforeStarting = "Before starting"
    static let timeCapsule = "Time Capsule"
    static let prerequisites: Set<String> = [beforeStarting, timeCapsule]
}

// MARK: - Execution results

enum ItemOutcome: String, Codable {
    case done = "Done"
    case wouldRemove = "Would remove (dry run)"
    case wouldRun = "Would run (dry run)"
    case skippedUnsafe = "Skipped (safety rule)"
    case skippedWhitelisted = "Skipped (whitelisted)"
    case skippedAfterFailure = "Skipped (earlier step failed)"
    case coveredByParent = "Included in its parent folder"
    case failed = "Failed"
}

struct ItemResult: Identifiable, Codable, Sendable {
    let id: UUID
    let item: ChangeItem
    let outcome: ItemOutcome
    let detail: String
    /// Where the item landed in the Trash — enables Restore from History.
    let trashedTo: String?

    init(item: ChangeItem, outcome: ItemOutcome, detail: String = "", trashedTo: String? = nil) {
        self.id = UUID()
        self.item = item
        self.outcome = outcome
        self.detail = detail
        self.trashedTo = trashedTo
    }
}

struct ExecutionResult: Sendable {
    let planTitle: String
    let dryRun: Bool
    let results: [ItemResult]
    let finishedAt = Date()

    /// Bytes moved to the Trash. They still take up disk space until the
    /// Trash is emptied.
    var trashedBytes: Int64 {
        results.filter { $0.outcome == .done && $0.item.action == .moveToTrash }
            .reduce(0) { $0 + $1.item.sizeBytes }
    }
    /// Bytes deleted outright (including emptying the Trash): space freed now.
    var deletedBytes: Int64 {
        results.filter { $0.outcome == .done && $0.item.action == .deletePermanently }
            .reduce(0) { $0 + $1.item.sizeBytes }
    }
    /// Everything removed from its original place, trashed or deleted.
    var removedBytes: Int64 { trashedBytes + deletedBytes }

    /// Honest one-liner: trashed bytes aren't free disk space yet.
    var removalSummary: String {
        var parts: [String] = []
        if trashedBytes > 0 { parts.append("Moved \(ByteFormat.string(trashedBytes)) to the Trash") }
        if deletedBytes > 0 {
            parts.append((parts.isEmpty ? "Deleted " : "deleted ") + ByteFormat.string(deletedBytes))
        }
        return parts.isEmpty ? "Nothing was removed" : parts.joined(separator: ", ")
    }
    var wouldFreeBytes: Int64 {
        results.filter { $0.outcome == .wouldRemove }.reduce(0) { $0 + $1.item.sizeBytes }
    }
    var failures: [ItemResult] { results.filter { $0.outcome == .failed } }
}

// MARK: - Overlapping targets

/// Cleanup categories overlap: User App Caches lists ~/Library/Caches/Google
/// while Browser Caches lists .../Google/Chrome inside it, and Orphaned App
/// Data repeats some Caches folders exactly. These helpers make sure the
/// same bytes are counted once and removed once.
enum TargetOverlap {

    static func isFileAction(_ item: ChangeItem) -> Bool {
        item.action == .moveToTrash || item.action == .deletePermanently
    }

    /// Comparison key for a file target (normalized, case-insensitive).
    static func key(_ item: ChangeItem) -> String {
        SafetyRules.pathKey(SafetyRules.normalize(item.target))
    }

    /// True when a proper ancestor folder of `key` is in `keys`.
    static func hasAncestor(_ key: String, in keys: Set<String>) -> Bool {
        var current = key
        while let slash = current.lastIndex(of: "/"), slash > current.startIndex {
            current = String(current[..<slash])
            if keys.contains(current) { return true }
        }
        return false
    }

    /// Total bytes, counting a repeated target once and skipping anything
    /// inside another listed folder (the folder's size already includes it).
    static func uniqueSize(of items: [ChangeItem]) -> Int64 {
        var sizeByKey: [String: Int64] = [:]
        var other: Int64 = 0
        for item in items {
            if isFileAction(item) {
                let k = key(item)
                sizeByKey[k] = max(sizeByKey[k] ?? 0, item.sizeBytes)
            } else {
                other += item.sizeBytes
            }
        }
        let keys = Set(sizeByKey.keys)
        return sizeByKey.reduce(other) { total, entry in
            hasAncestor(entry.key, in: keys) ? total : total + entry.value
        }
    }

    /// Execution order: file targets shallowest first (parents before
    /// children), otherwise in their original order. Non-file steps keep
    /// their positions, so prerequisite steps still run first.
    static func executionOrder(_ items: [ChangeItem]) -> [ChangeItem] {
        let fileSlots = items.indices.filter { isFileAction(items[$0]) }
        let sortedFiles = fileSlots.enumerated()
            .map { (order: $0.offset, item: items[$0.element]) }
            .sorted { a, b in
                let da = depth(a.item), db = depth(b.item)
                return da != db ? da < db : a.order < b.order
            }
            .map { $0.item }
        var result = items
        for (slot, item) in zip(fileSlots, sortedFiles) { result[slot] = item }
        return result
    }

    static func depth(_ item: ChangeItem) -> Int {
        key(item).split(separator: "/").count
    }
}

// MARK: - Byte formatting

enum ByteFormat {
    static func string(_ bytes: Int64) -> String {
        let fmt = ByteCountFormatter()
        fmt.countStyle = .file
        return fmt.string(fromByteCount: bytes)
    }
}
