import Foundation

struct AutopilotRule: Identifiable, Codable {
    enum Frequency: String, Codable, CaseIterable {
        case daily = "Daily"
        case weekly = "Weekly"
        case monthly = "Monthly"

        var interval: TimeInterval {
            switch self {
            case .daily: return 86_400
            case .weekly: return 7 * 86_400
            case .monthly: return 30 * 86_400
            }
        }
    }

    var id = UUID()
    var name: String
    var categoryIDs: [String]
    var frequency: Frequency
    var isEnabled = true
    var lastRun: Date? = nil
    var lastFreedBytes: Int64 = 0
    /// Optional for backward-compatible decoding of rules saved before this
    /// field existed.
    var createdAt: Date? = nil

    /// A rule's first scheduled run is one full interval after creation —
    /// never immediately, so authoring a rule is never itself destructive.
    /// Use "Run Now" for an immediate run.
    var isDue: Bool {
        let reference = lastRun ?? createdAt ?? .distantPast
        return isEnabled && reference.addingTimeInterval(frequency.interval) < Date()
    }
}

/// Scheduled cleaning rules — the 2.0 flagship.
///
/// Safety model: Autopilot only runs cleanup categories the user explicitly
/// put in a rule they authored. Risky categories (build artifacts, orphans)
/// are not eligible at all. Every run is a normal ChangePlan execution:
/// items re-validated by SafetyRules, trash-first, fully logged in History,
/// high-risk items never included, and a notification reports the outcome.
final class Autopilot: ObservableObject {

    static let shared = Autopilot()

    /// Categories a rule may include. Artifacts and orphans require human
    /// judgment and stay manual-only. The Trash category is eligible but its
    /// permanence is called out in the rule editor.
    static let excludedCategoryIDs: Set<String> = ["artifacts", "orphans"]

    static var eligibleCategories: [CleanupCategory] {
        CleanupScanner.categories().filter { !excludedCategoryIDs.contains($0.id) }
    }

    @Published var rules: [AutopilotRule] = [] {
        didSet { if !isLoading { save() } }
    }
    @Published private(set) var running = false

    private var isLoading = false
    private var timer: Timer?

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Marmot", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("autopilot.json")
    }

    private init() {
        isLoading = true
        load()
        isLoading = false
    }

    // MARK: - Scheduling

    /// Called once at launch (from the app delegate, on the main thread).
    func start() {
        // First check shortly after launch, then hourly.
        Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { _ in
            Task { @MainActor in Autopilot.shared.checkDueRules() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { @MainActor in Autopilot.shared.checkDueRules() }
        }
    }

    func checkDueRules() {
        guard !running else { return }
        if let due = rules.first(where: { $0.isDue }) {
            run(due)
        }
    }

    // MARK: - Execution

    /// Runs one rule: fresh scan of its categories, then a normal trash-first
    /// plan execution. Never dry — the user opted in by authoring the rule.
    func run(_ rule: AutopilotRule) {
        guard !running else { return }
        running = true
        let categoryIDs = rule.categoryIDs.filter { !Self.excludedCategoryIDs.contains($0) }

        Task { @MainActor in
            defer { self.running = false }

            let items = await Task.detached(priority: .utility) {
                categoryIDs.flatMap { CleanupScanner.scan(categoryID: $0) }
            }.value.filter(\.isSelected) // respects conservative default selections

            guard !items.isEmpty else {
                self.markRan(rule, freed: 0)
                return
            }

            let plan = ChangePlan(title: "Autopilot — \(rule.name)",
                                  source: "Autopilot", items: items)
            let result = await PlanExecutor.execute(plan, dryRun: false, allowPurgeRoots: false)

            self.markRan(rule, freed: result.freedBytes)
            Notifier.post(
                title: "Autopilot: \(rule.name)",
                body: result.freedBytes > 0
                    ? "Freed \(ByteFormat.string(result.freedBytes)). Everything is logged in History and restorable from the Trash."
                    : "Nothing to clean this time.",
                identifier: "marmot.autopilot.\(rule.id)")
            CleanupModel.shared.rescan()
        }
    }

    private func markRan(_ rule: AutopilotRule, freed: Int64) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index].lastRun = Date()
        rules[index].lastFreedBytes = freed
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        rules = (try? decoder.decode([AutopilotRule].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(rules) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
