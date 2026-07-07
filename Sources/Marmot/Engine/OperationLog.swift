import Foundation

/// Append-only JSONL log of everything Marmot did (or would have done in a dry
/// run). Mirrors `mo history`. Stored in ~/Library/Application Support/Marmot/.
struct LogEntry: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let source: String
    let dryRun: Bool
    let action: String
    let target: String
    let sizeBytes: Int64
    let outcome: String
}

final class OperationLog {
    static let shared = OperationLog()

    private let queue = DispatchQueue(label: "marmot.oplog")
    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Marmot", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("operations.jsonl")
    }

    func record(_ result: ExecutionResult, source: String) {
        queue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var lines: [Data] = []
            for r in result.results {
                let entry = LogEntry(
                    date: result.finishedAt,
                    source: source,
                    dryRun: result.dryRun,
                    action: r.item.action.rawValue,
                    target: r.item.target,
                    sizeBytes: r.item.sizeBytes,
                    outcome: r.outcome.rawValue
                )
                if let data = try? encoder.encode(entry) {
                    lines.append(data)
                }
            }
            guard !lines.isEmpty else { return }
            let blob = lines.map { String(data: $0, encoding: .utf8) ?? "" }
                .joined(separator: "\n") + "\n"
            if let handle = try? FileHandle(forWritingTo: self.fileURL) {
                handle.seekToEndOfFile()
                handle.write(blob.data(using: .utf8)!)
                try? handle.close()
            } else {
                try? blob.data(using: .utf8)?.write(to: self.fileURL)
            }
        }
    }

    func readAll() -> [LogEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return Array(text.split(separator: "\n").compactMap { line in
            try? decoder.decode(LogEntry.self, from: Data(line.utf8))
        }.reversed())
    }

    func clear() {
        queue.async { try? FileManager.default.removeItem(at: self.fileURL) }
    }
}
