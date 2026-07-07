import Foundation

struct StartupItem: Identifiable {
    enum Kind: String, CaseIterable {
        case loginItem = "Login Items"
        case userAgent = "Launch Agents (yours)"
        case systemAgent = "Launch Agents (all users)"
        case systemDaemon = "Launch Daemons (system)"
    }

    let id: String
    let kind: Kind
    let name: String
    let detail: String       // program path, or a hint for login items
    let plistPath: String?   // nil for login items
    let runAtLoad: Bool
    let keepAlive: Bool
}

/// Lists everything that starts automatically: login items plus third-party
/// launch agents and daemons. Removal goes through ChangePlans like all else.
enum StartupEngine {

    static func all() -> [StartupItem] {
        loginItems()
            + agents(in: SafetyRules.home + "/Library/LaunchAgents", kind: .userAgent)
            + agents(in: "/Library/LaunchAgents", kind: .systemAgent)
            + agents(in: "/Library/LaunchDaemons", kind: .systemDaemon)
    }

    /// Login items via System Events (triggers the one-time Automation prompt).
    static func loginItems() -> [StartupItem] {
        let script = "tell application \"System Events\" to get the name of every login item"
        let out = Shell.run("/usr/bin/osascript", ["-e", script], timeout: 15)
        guard out.succeeded else { return [] }
        let list = out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !list.isEmpty else { return [] }
        return list.components(separatedBy: ", ").map { name in
            StartupItem(id: "login:" + name,
                        kind: .loginItem,
                        name: name,
                        detail: "Opens at login (System Settings → General → Login Items)",
                        plistPath: nil,
                        runAtLoad: true,
                        keepAlive: false)
        }
    }

    static func agents(in dir: String, kind: StartupItem.Kind) -> [StartupItem] {
        CleanupScanner.children(of: dir)
            .filter { $0.hasSuffix(".plist") }
            .compactMap { path in
                let fileName = (path as NSString).lastPathComponent
                // Third-party only in system locations.
                if kind != .userAgent && fileName.lowercased().hasPrefix("com.apple.") { return nil }

                var label = (fileName as NSString).deletingPathExtension
                var program = ""
                var runAtLoad = false
                var keepAlive = false
                if let data = FileManager.default.contents(atPath: path),
                   let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                    label = (plist["Label"] as? String) ?? label
                    program = (plist["Program"] as? String)
                        ?? (plist["ProgramArguments"] as? [String])?.first
                        ?? ""
                    runAtLoad = (plist["RunAtLoad"] as? Bool) ?? false
                    if let value = plist["KeepAlive"] {
                        keepAlive = (value as? Bool) ?? true // dict forms mean "conditionally alive"
                    }
                }
                return StartupItem(id: path,
                                   kind: kind,
                                   name: label,
                                   detail: program.isEmpty ? path : program,
                                   plistPath: path,
                                   runAtLoad: runAtLoad,
                                   keepAlive: keepAlive)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func removalPlan(for item: StartupItem) -> ChangePlan {
        var items: [ChangeItem] = []
        switch item.kind {
        case .loginItem:
            items.append(ChangeItem(
                target: "osascript -e 'tell application \"System Events\" to delete login item \"\(item.name)\"'",
                action: .runCommand,
                risk: .low,
                note: "Removes the login item entry only — the app itself stays installed.",
                group: item.kind.rawValue))

        case .userAgent:
            guard let path = item.plistPath else { break }
            items.append(ChangeItem(
                target: "launchctl bootout gui/$UID \"\(path)\" 2>/dev/null; true",
                action: .runCommand,
                risk: .low,
                note: "Stops the agent if it is currently running.",
                group: item.kind.rawValue))
            items.append(ChangeItem(
                target: path,
                action: .moveToTrash,
                sizeBytes: FileSizer.size(of: path),
                risk: .low,
                note: "The agent's launchd configuration file (recoverable from Trash). The app it belongs to is not deleted.",
                group: item.kind.rawValue))

        case .systemAgent, .systemDaemon:
            guard let path = item.plistPath else { break }
            items.append(ChangeItem(
                target: "launchctl bootout system \"\(path)\" 2>/dev/null; mv \"\(path)\" \"$HOME/.Trash/\"",
                action: .runAdminCommand,
                risk: .medium,
                note: "Stops the item and moves its configuration to your Trash (recoverable). The app it belongs to is not deleted.",
                group: item.kind.rawValue))
        }
        return ChangePlan(title: "Remove \(item.name) from startup",
                          source: "Startup Items",
                          items: items)
    }
}
