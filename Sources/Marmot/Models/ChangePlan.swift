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

struct ChangeItem: Identifiable, Codable, Hashable {
    let id: UUID
    /// Filesystem path for file actions, or the shell command for command actions.
    let target: String
    let action: ChangeAction
    let sizeBytes: Int64
    let risk: RiskLevel
    /// Human explanation of what this is and why it is safe (or not) to remove.
    let note: String
    /// Group label used by the preview UI (e.g. "Caches", "Launch Agents").
    let group: String
    var isSelected: Bool

    init(target: String,
         action: ChangeAction,
         sizeBytes: Int64 = 0,
         risk: RiskLevel = .low,
         note: String = "",
         group: String = "General",
         isSelected: Bool = true) {
        self.id = UUID()
        self.target = target
        self.action = action
        self.sizeBytes = sizeBytes
        self.risk = risk
        self.note = note
        self.group = group
        // High-risk items are never pre-selected.
        self.isSelected = isSelected && risk != .high
    }

    var displayName: String {
        if action == .runCommand || action == .runAdminCommand { return target }
        return (target as NSString).lastPathComponent
    }
}

struct ChangePlan: Identifiable {
    let id = UUID()
    let title: String
    /// Where this plan came from, e.g. "Cleanup", "Uninstall Photoshop".
    let source: String
    var items: [ChangeItem]
    let createdAt = Date()

    var selectedItems: [ChangeItem] { items.filter { $0.isSelected } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.sizeBytes } }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
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

// MARK: - Execution results

enum ItemOutcome: String, Codable {
    case done = "Done"
    case wouldRemove = "Would remove (dry run)"
    case wouldRun = "Would run (dry run)"
    case skippedUnsafe = "Skipped (safety rule)"
    case skippedWhitelisted = "Skipped (whitelisted)"
    case failed = "Failed"
}

struct ItemResult: Identifiable, Codable {
    let id: UUID
    let item: ChangeItem
    let outcome: ItemOutcome
    let detail: String

    init(item: ChangeItem, outcome: ItemOutcome, detail: String = "") {
        self.id = UUID()
        self.item = item
        self.outcome = outcome
        self.detail = detail
    }
}

struct ExecutionResult {
    let planTitle: String
    let dryRun: Bool
    let results: [ItemResult]
    let finishedAt = Date()

    var freedBytes: Int64 {
        results.filter { $0.outcome == .done && ($0.item.action == .moveToTrash || $0.item.action == .deletePermanently) }
            .reduce(0) { $0 + $1.item.sizeBytes }
    }
    var wouldFreeBytes: Int64 {
        results.filter { $0.outcome == .wouldRemove }.reduce(0) { $0 + $1.item.sizeBytes }
    }
    var failures: [ItemResult] { results.filter { $0.outcome == .failed } }
}

// MARK: - Byte formatting

enum ByteFormat {
    static func string(_ bytes: Int64) -> String {
        let fmt = ByteCountFormatter()
        fmt.countStyle = .file
        return fmt.string(fromByteCount: bytes)
    }
}
