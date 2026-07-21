import SwiftUI

/// Command-palette (⌘K) item builders — static entries for every tool and
/// action, plus query-aware intents ("uninstall slack", "files over 2gb").
extension MainWindow {

    var paletteItems: [PaletteItem] {
        var items = SidebarSection.allCases.map { section in
            PaletteItem(title: section.rawValue, subtitle: section.blurb,
                        icon: section.icon) { selection = section }
        }
        items.append(PaletteItem(
            title: "Smart Scan",
            subtitle: "Scan all cleanup categories now",
            icon: "wand.and.stars") {
                selection = .cleanup
                CleanupModel.shared.rescan()
            })
        items.append(PaletteItem(
            title: "Check for Updates",
            subtitle: "See if a newer Marmot is available",
            icon: "arrow.down.circle") {
                UpdaterBridge.shared.checkForUpdates()
            })
        for rule in Autopilot.shared.rules where rule.isEnabled {
            items.append(PaletteItem(
                title: "Run rule: \(rule.name)",
                subtitle: "Autopilot — \(rule.frequency.rawValue)",
                icon: "clock.badge.checkmark") {
                    selection = .autopilot
                    Autopilot.shared.run(rule)
                })
        }
        return items
    }

    /// Query-aware palette items: parsed intents ranked above the static list.
    func dynamicPaletteItems(for query: String) -> [PaletteItem] {
        var items: [PaletteItem] = []

        if let bigQuery = IntentParser.bigFilesQuery(from: query) {
            let sizeText = bigQuery.minSizeMB >= 1000
                ? "\(bigQuery.minSizeMB / 1000) GB+"
                : "\(bigQuery.minSizeMB) MB+"
            let ageText = bigQuery.minAgeDays >= 365 ? ", 1+ year old"
                : (bigQuery.minAgeDays >= 180 ? ", 6+ months old" : "")
            items.append(PaletteItem(
                title: "Hunt files \(sizeText)\(ageText)",
                subtitle: "Big Files with these filters applied",
                icon: "externaldrive") {
                    selection = .bigFiles
                    DeepLink.post(.marmotBigFilesIntent,
                                  userInfo: ["minSizeMB": bigQuery.minSizeMB,
                                             "minAgeDays": bigQuery.minAgeDays])
                })
        }

        if let action = IntentParser.appAction(from: query) {
            let matches = AppInventory.shared.apps
                .filter { $0.name.localizedCaseInsensitiveContains(action.name) }
                .prefix(3)
            for app in matches {
                let reset = action.reset
                items.append(PaletteItem(
                    title: "\(reset ? "Reset" : "Uninstall") \(app.name)",
                    subtitle: reset ? "Clear its data, keep the app" : "App + all leftovers, previewed first",
                    icon: reset ? "arrow.counterclockwise" : "trash") {
                        selection = .uninstall
                        DeepLink.post(.marmotUninstallIntent,
                                      userInfo: ["appPath": app.id, "reset": reset])
                    })
            }
        }
        return items
    }
}
