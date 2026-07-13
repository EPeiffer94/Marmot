import SwiftUI

struct SettingsView: View {

    @AppStorage(Prefs.defaultDryRun) private var defaultDryRun = true
    @AppStorage(Prefs.hudEnabled) private var hudEnabled = true
    @State private var whitelist: [String] = SafetyRules.whitelist
    @State private var newPath = ""
    @State private var purgePaths: [String] = UserDefaults.standard.stringArray(forKey: Prefs.purgePaths) ?? []
    @State private var newPurgePath = ""

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            whitelistTab
                .tabItem { Label("Protected Paths", systemImage: "shield") }
            purgeTab
                .tabItem { Label("Project Folders", systemImage: "folder.badge.gearshape") }
        }
        .frame(width: 520, height: 380)
    }

    @AppStorage(Prefs.junkAlertGB) private var junkAlertGB = 0

    private var generalTab: some View {
        Form {
            Toggle("Show menu bar HUD", isOn: $hudEnabled)
            Toggle("Suggest dry run before applying", isOn: $defaultDryRun)
            Picker("Junk alert in menu bar", selection: $junkAlertGB) {
                Text("Off").tag(0)
                Text("Over 5 GB").tag(5)
                Text("Over 10 GB").tag(10)
                Text("Over 25 GB").tag(25)
                Text("Over 50 GB").tag(50)
            }
            Text("With the alert on, Marmot quietly rescans every few hours and shows ⚠︎ next to the menu bar reading when reclaimable junk crosses the threshold.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Marmot never removes anything without showing you the full change plan first. Files go to the Trash by default so they stay recoverable.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            HStack {
                Button("Check for Updates…") {
                    UpdaterBridge.shared.checkForUpdates()
                }
                .disabled(!UpdaterBridge.shared.isActive)
                if !UpdaterBridge.shared.isActive {
                    Text("Updates unavailable in this build.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding()
    }

    private var whitelistTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paths listed here are never touched by any cleanup or uninstall plan.")
                .font(.caption)
                .foregroundStyle(.secondary)
            List {
                ForEach(whitelist, id: \.self) { path in
                    HStack {
                        Text(path).font(.callout.monospaced())
                        Spacer()
                        Button {
                            whitelist.removeAll { $0 == path }
                            SafetyRules.whitelist = whitelist
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                TextField("~/Library/Caches/something-important", text: $newPath)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let path = SafetyRules.normalize(newPath)
                    guard !path.isEmpty, !whitelist.contains(path) else { return }
                    whitelist.append(path)
                    SafetyRules.whitelist = whitelist
                    newPath = ""
                }
                .disabled(newPath.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
    }

    private var purgeTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Extra folders scanned for project build artifacts (node_modules, target, dist…). Defaults: ~/Projects, ~/GitHub, ~/dev, ~/Code, ~/repos.")
                .font(.caption)
                .foregroundStyle(.secondary)
            List {
                ForEach(purgePaths, id: \.self) { path in
                    HStack {
                        Text(path).font(.callout.monospaced())
                        Spacer()
                        Button {
                            purgePaths.removeAll { $0 == path }
                            UserDefaults.standard.set(purgePaths, forKey: Prefs.purgePaths)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                TextField("~/Work/ClientProjects", text: $newPurgePath)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let path = SafetyRules.normalize(newPurgePath)
                    guard !path.isEmpty, !purgePaths.contains(path) else { return }
                    purgePaths.append(path)
                    UserDefaults.standard.set(purgePaths, forKey: Prefs.purgePaths)
                    newPurgePath = ""
                }
                .disabled(newPurgePath.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
    }
}
