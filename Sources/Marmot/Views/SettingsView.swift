import SwiftUI
import AppKit

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
            supportTab
                .tabItem { Label("Support", systemImage: "heart") }
        }
        .frame(width: 520, height: 380)
        // Covers the standalone ⌘, window too (it's outside MainWindow's tint).
        .tint(Theme.palette(named: accentName)?.accent ?? .mint)
    }

    @AppStorage(Prefs.supporter) private var supporter = false

    private var supportTab: some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Theme.wash(Theme.slot(0, classic: .pink)))
                    .frame(width: 92, height: 92)
                Text("🐿️")
                    .font(.system(size: 44))
            }
            Text("Marmot is free forever")
                .font(.title3.weight(.semibold))
            Text("No upsells, no license keys — that's the promise. If Marmot has saved you gigabytes and you'd like to feed the marmot, here's the tip jar.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            HStack(spacing: 10) {
                Button {
                    NSWorkspace.shared.open(Support.repoURL)
                } label: {
                    Label("Star on GitHub", systemImage: "star")
                }
                if let url = Support.sponsorsURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Sponsor", systemImage: "heart.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                }
                if let url = Support.coffeeURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Buy a Coffee", systemImage: "cup.and.saucer")
                    }
                }
            }
            Toggle("I already support Marmot (hides the occasional nudge)", isOn: $supporter)
                .font(.caption)
                .padding(.top, 6)
            Spacer()
        }
        .padding()
    }

    @AppStorage(Prefs.junkAlertGB) private var junkAlertGB = 0
    @AppStorage(Prefs.watchtowerDays) private var watchtowerDays = 0
    @AppStorage(Prefs.sentinelEnabled) private var sentinelEnabled = true
    @AppStorage(Prefs.accent) private var accentName = ""
    @AppStorage(Prefs.healthAlertBelow) private var healthAlertBelow = 0

    private var generalTab: some View {
        Form {
            Toggle("Show menu bar HUD", isOn: $hudEnabled)
            Toggle("Suggest dry run before applying", isOn: $defaultDryRun)
            Group {
                Toggle("Alert when new startup items appear", isOn: $sentinelEnabled)
                    .onChange(of: sentinelEnabled) { on in
                        if on {
                            StartupSentinel.shared.start()
                        } else {
                            StartupSentinel.shared.stop()
                        }
                    }
                Picker("Health alert", selection: $healthAlertBelow) {
                    Text("Off").tag(0)
                    Text("Below 70").tag(70)
                    Text("Below 50").tag(50)
                    Text("Below 30").tag(30)
                }
                accentRow
            }
            Picker("Watch for app updates", selection: $watchtowerDays) {
                Text("Off").tag(0)
                Text("Daily").tag(1)
                Text("Weekly").tag(7)
            }
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

    /// Theme swatches — every theme is multi-colored (never monochrome).
    /// "Classic" is the original hand-tuned mint/green/pink/blue scheme;
    /// the others cycle their own pastel families across the modules.
    private var accentRow: some View {
        HStack(spacing: 8) {
            Text("Color theme")
            Spacer()
            swatch(selected: accentName.isEmpty,
                   fill: AngularGradient(colors: [.mint, .green, .pink, .blue, .mint],
                                         center: .center),
                   name: "Classic") {
                accentName = ""
            }
            ForEach(Theme.palettes, id: \.name) { palette in
                swatch(selected: palette.name == accentName,
                       fill: AngularGradient(colors: palette.colors + [palette.colors[0]],
                                             center: .center),
                       name: palette.name) {
                    accentName = palette.name
                }
            }
        }
    }

    private func swatch<S: ShapeStyle>(selected: Bool, fill: S, name: String,
                                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(fill)
                .frame(width: 18, height: 18)
                .overlay(
                    Circle().strokeBorder(
                        Color.primary.opacity(selected ? 0.55 : 0), lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel("\(name) accent\(selected ? ", selected" : "")")
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
