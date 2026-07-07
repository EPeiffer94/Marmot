import Foundation

struct MaintenanceTask: Identifiable {
    let id: String
    let name: String
    let icon: String
    let explanation: String
    let effect: String              // what will visibly change
    let commands: [(String, Bool)]  // (command, needsAdmin)
    let risk: RiskLevel
    /// If set, the task is only offered when this binary exists — some tools
    /// (e.g. `periodic`) were removed from modern macOS releases.
    var requiredBinary: String? = nil

    /// Turn this task into a reviewable plan.
    func plan() -> ChangePlan {
        let items = commands.map { cmd, admin in
            ChangeItem(target: cmd,
                       action: admin ? .runAdminCommand : .runCommand,
                       sizeBytes: 0,
                       risk: risk,
                       note: explanation,
                       group: name,
                       isSelected: true)
        }
        return ChangePlan(title: name, source: "Maintenance", items: items)
    }
}

enum MaintenanceCatalog {

    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    static var all: [MaintenanceTask] {
        catalog.filter { task in
            guard let binary = task.requiredBinary else { return true }
            return FileManager.default.fileExists(atPath: binary)
        }
    }

    static var catalog: [MaintenanceTask] {
        [
            MaintenanceTask(
                id: "dns", name: "Flush DNS Cache", icon: "network",
                explanation: "Clears the system DNS resolver cache. Fixes stale name lookups after network or VPN changes.",
                effect: "Websites re-resolve on next access; momentary DNS slowdown.",
                commands: [
                    ("/usr/bin/dscacheutil -flushcache", false),
                    ("/usr/bin/killall -HUP mDNSResponder", true)
                ],
                risk: .low),
            MaintenanceTask(
                id: "launchservices", name: "Rebuild Launch Services", icon: "square.grid.2x2",
                explanation: "Rebuilds the database that maps file types to apps. Fixes duplicate entries in Open With menus.",
                effect: "Open With menus reset; first rebuild takes a minute.",
                commands: [
                    ("\(lsregister) -kill -r -domain local -domain system -domain user", false)
                ],
                risk: .medium),
            MaintenanceTask(
                id: "finder", name: "Refresh Finder", icon: "faceid",
                explanation: "Restarts Finder to clear icon and listing glitches.",
                effect: "Finder windows close and reopen.",
                commands: [("/usr/bin/killall Finder", false)],
                risk: .low),
            MaintenanceTask(
                id: "dock", name: "Refresh Dock", icon: "dock.rectangle",
                explanation: "Restarts the Dock process to fix rendering or Mission Control glitches.",
                effect: "The Dock disappears for a second and returns.",
                commands: [("/usr/bin/killall Dock", false)],
                risk: .low),
            MaintenanceTask(
                id: "fonts", name: "Clear Font Caches", icon: "textformat",
                explanation: "Removes corrupted font caches that cause garbled text.",
                effect: "Requires a restart to fully take effect.",
                commands: [("/usr/bin/atsutil databases -remove", true)],
                risk: .medium,
                requiredBinary: "/usr/bin/atsutil"),
            MaintenanceTask(
                id: "spotlight", name: "Rebuild Spotlight Index", icon: "magnifyingglass",
                explanation: "Erases and rebuilds the Spotlight index for the boot volume. Fixes missing search results.",
                effect: "Search results incomplete for up to a few hours while reindexing.",
                commands: [("/usr/bin/mdutil -E /", true)],
                risk: .medium),
            MaintenanceTask(
                id: "diaglogs", name: "Clean Diagnostic Reports", icon: "waveform.path.ecg",
                explanation: "Removes accumulated crash and diagnostic reports.",
                effect: "Old crash reports are no longer available to inspect.",
                commands: [
                    ("/bin/rm -rf ~/Library/Logs/DiagnosticReports/*", false),
                    ("/bin/rm -rf /Library/Logs/DiagnosticReports/*", true)
                ],
                risk: .low),
            MaintenanceTask(
                id: "purgemem", name: "Purge Memory Cache", icon: "memorychip",
                explanation: "Forces the file-system cache to be flushed, freeing inactive memory.",
                effect: "Brief system pause; apps may reload cached data.",
                commands: [("/usr/sbin/purge", true)],
                risk: .low,
                requiredBinary: "/usr/sbin/purge"),
            MaintenanceTask(
                id: "maintenance", name: "Run Periodic Scripts", icon: "clock.arrow.circlepath",
                explanation: "Runs the traditional daily/weekly/monthly system maintenance scripts.",
                effect: "Rotates logs and cleans temporary system files.",
                commands: [("/usr/sbin/periodic daily weekly monthly", true)],
                risk: .low,
                requiredBinary: "/usr/sbin/periodic")
        ]
    }
}
