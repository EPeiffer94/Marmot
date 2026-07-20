import Foundation

/// Written from exactly one drain thread, read only after the group waits.
private final class DataBox: @unchecked Sendable {
    var data = Data()
}

enum Shell {
    struct Output {
        let status: Int32
        let stdout: String
        let stderr: String
        var succeeded: Bool { status == 0 }
    }

    /// Run a command without a shell (argv form) — used for known binaries.
    /// Output is drained concurrently so large output cannot deadlock the pipe.
    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval = 120) -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        let outBox = DataBox()
        let errBox = DataBox()
        let drainGroup = DispatchGroup()
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            return Output(status: -1, stdout: "", stderr: error.localizedDescription)
        }

        drainGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            outBox.data = out.fileHandleForReading.readDataToEndOfFile()
            drainGroup.leave()
        }
        drainGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            errBox.data = err.fileHandleForReading.readDataToEndOfFile()
            drainGroup.leave()
        }

        // Event-driven wait (no polling); escalate to terminate on timeout.
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 5) == .timedOut {
                return Output(status: -1, stdout: "", stderr: "Timed out: \(launchPath)")
            }
        }
        drainGroup.wait()

        return Output(status: process.terminationStatus,
                      stdout: String(data: outBox.data, encoding: .utf8) ?? "",
                      stderr: String(data: errBox.data, encoding: .utf8) ?? "")
    }

    /// Run a shell one-liner via /bin/zsh -c.
    @discardableResult
    static func runLine(_ command: String, timeout: TimeInterval = 120) -> Output {
        run("/bin/zsh", ["-c", command], timeout: timeout)
    }

    /// POSIX single-quote escaping — the ONLY safe way to splice a filename
    /// into a shell line. Inside single quotes nothing expands; embedded
    /// single quotes become '\'' (close, escaped quote, reopen).
    static func quoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// An AppleScript string literal with backslashes and quotes escaped.
    static func appleScriptString(_ s: String) -> String {
        "\"" + s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Run with administrator privileges. macOS shows the standard auth prompt.
    @discardableResult
    static func runAdmin(_ command: String) -> Output {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        return run("/usr/bin/osascript", ["-e", script], timeout: 300)
    }

    static func exists(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    static var brewPath: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: exists)
    }
}
