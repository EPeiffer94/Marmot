import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case cleanup = "Cleanup"
    case autopilot = "Autopilot"
    case uninstall = "Uninstaller"
    case unusedApps = "Unused Apps"
    case updates = "App Updates"
    case duplicates = "Duplicates"
    case bigFiles = "Big Files"
    case diskMap = "Disk Map"
    case startup = "Startup Items"
    case maintenance = "Maintenance"
    case status = "Live Status"
    case history = "History"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "house"
        case .cleanup: return "sparkles"
        case .autopilot: return "clock.badge.checkmark"
        case .uninstall: return "trash.square"
        case .unusedApps: return "hourglass"
        case .updates: return "arrow.down.app"
        case .duplicates: return "doc.on.doc"
        case .bigFiles: return "externaldrive"
        case .diskMap: return "square.grid.3x3.topleft.filled"
        case .startup: return "power"
        case .maintenance: return "wrench.and.screwdriver"
        case .status: return "gauge.with.needle"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }

    /// One-line description used by the Dashboard shortcut grid.
    var blurb: String {
        switch self {
        case .dashboard: return "System overview"
        case .cleanup: return "Reclaim disk space safely"
        case .autopilot: return "Scheduled cleaning rules"
        case .uninstall: return "Remove apps and their leftovers"
        case .unusedApps: return "Find apps you never open"
        case .updates: return "Check for newer versions"
        case .duplicates: return "Find identical files"
        case .bigFiles: return "Hunt huge, forgotten files"
        case .diskMap: return "See where space goes"
        case .startup: return "Manage login and launch items"
        case .maintenance: return "Fix common system glitches"
        case .status: return "Live CPU, memory, network"
        case .history: return "Everything Marmot has done"
        case .settings: return "Preferences, protection, support"
        }
    }
}

extension Notification.Name {
    /// Posted by the menu bar HUD's gear button to open Settings in-window.
    static let marmotOpenSettings = Notification.Name("marmot.openSettings")
    /// Smart-palette deep link: userInfo minSizeMB/minAgeDays.
    static let marmotBigFilesIntent = Notification.Name("marmot.bigFilesIntent")
    /// Smart-palette deep link: userInfo appPath/reset.
    static let marmotUninstallIntent = Notification.Name("marmot.uninstallIntent")
    /// An .app was dropped on the window or Dock icon: userInfo appPath.
    static let marmotDroppedApp = Notification.Name("marmot.droppedApp")
    /// A plan was applied for real: userInfo result (ExecutionResult).
    static let marmotPlanApplied = Notification.Name("marmot.planApplied")
}

/// Transient bottom toast after a real (non-dry-run) clean.
struct FreedToast: Identifiable {
    let id = UUID()
    var freed: Int64 = 0
    var restorables: [ItemResult] = []
    var restoredMessage: String?
}

struct MainWindow: View {
    @State private var selection: SidebarSection?
    @State private var showPalette = false
    @State private var dropTargeted = false
    @State private var toast: FreedToast?
    @EnvironmentObject var stats: StatsSampler
    @AppStorage(Prefs.onboarded) private var onboarded = false
    @AppStorage(Prefs.accent) private var accentName = ""

    /// ⌘1–⌘9 jump to the first nine sections in sidebar order.
    private static let quickSections: [SidebarSection] = [
        .dashboard, .cleanup, .autopilot, .duplicates, .bigFiles,
        .uninstall, .unusedApps, .updates, .diskMap
    ]

    init() {
        // Launch memory: reopen on the section you were last using.
        let saved = UserDefaults.standard.string(forKey: Prefs.lastSection)
        _selection = State(initialValue: saved.flatMap(SidebarSection.init(rawValue:)) ?? .dashboard)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                sidebarRow(.dashboard)
                Section("Clean") {
                    sidebarRow(.cleanup)
                    sidebarRow(.autopilot)
                    sidebarRow(.duplicates)
                    sidebarRow(.bigFiles)
                }
                Section("Apps") {
                    sidebarRow(.uninstall)
                    sidebarRow(.unusedApps)
                    sidebarRow(.updates)
                }
                Section("System") {
                    sidebarRow(.diskMap)
                    sidebarRow(.startup)
                    sidebarRow(.maintenance)
                    sidebarRow(.status)
                }
                Section("Activity") {
                    sidebarRow(.history)
                    sidebarRow(.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                sidebarFooter
            }
        } detail: {
            switch selection ?? .dashboard {
            case .dashboard: DashboardView { selection = $0 }
            case .cleanup: CleanupView()
            case .autopilot: AutopilotView()
            case .uninstall: UninstallView()
            case .unusedApps: UnusedAppsView()
            case .updates: UpdatesView()
            case .duplicates: DuplicatesView()
            case .bigFiles: BigFilesView()
            case .diskMap: DiskMapView()
            case .startup: StartupItemsView()
            case .maintenance: MaintenanceView()
            case .status: StatusView()
            case .history: HistoryView()
            case .settings:
                SettingsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .tint(Theme.palette(named: accentName)?.accent ?? .mint)
        .navigationTitle("Marmot")
        .background(
            // Hidden triggers: ⌘K palette + ⌘1–9 section jumps.
            Group {
                Button("") {
                    showPalette = true
                    AppInventory.shared.loadIfNeeded() // for "uninstall <app>" intents
                }
                .keyboardShortcut("k", modifiers: .command)
                ForEach(Array(Self.quickSections.enumerated()), id: \.offset) { index, section in
                    Button("") { selection = section }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
            .hidden()
        )
        .onChange(of: selection) { newValue in
            guard let newValue else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: Prefs.lastSection)
        }
        .overlay {
            if showPalette {
                CommandPaletteView(items: paletteItems,
                                   dynamicItems: dynamicPaletteItems) { showPalette = false }
            }
        }
        .overlay {
            if dropTargeted { dropOverlay }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                toastView(toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task(id: toast?.id) {
            // Toasts dismiss themselves after a few seconds.
            guard toast != nil else { return }
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.25)) { toast = nil }
            }
        }
        .sheet(isPresented: Binding(
            get: { !onboarded },
            set: { if !$0 { onboarded = true } }
        )) {
            OnboardingView { onboarded = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .marmotOpenSettings)) { _ in
            selection = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .marmotDroppedApp)) { note in
            guard let path = note.userInfo?["appPath"] as? String else { return }
            selection = .uninstall
            AppInventory.shared.loadIfNeeded()
            // Give the Uninstaller a beat to mount before it receives the intent.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NotificationCenter.default.post(
                    name: .marmotUninstallIntent, object: nil,
                    userInfo: ["appPath": path, "reset": false])
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .marmotPlanApplied)) { note in
            guard let result = note.userInfo?["result"] as? ExecutionResult,
                  result.freedBytes > 0 else { return }
            let restorables = result.results.filter {
                $0.trashedTo != nil && $0.outcome == .done
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                toast = FreedToast(freed: result.freedBytes, restorables: restorables)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            var handled = false
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.pathExtension == "app" else { return }
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: .marmotDroppedApp, object: nil,
                            userInfo: ["appPath": url.path])
                    }
                }
                handled = true
            }
            return handled
        }
    }

    /// CleanMyMac-style row: white glyph on the module's pastel squircle.
    private func sidebarRow(_ section: SidebarSection) -> some View {
        Label {
            Text(section.rawValue)
        } icon: {
            Image(systemName: section.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 21, height: 21)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.color(for: section).gradient)
                )
        }
        .tag(section)
    }

    private var paletteItems: [PaletteItem] {
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
    private func dynamicPaletteItems(for query: String) -> [PaletteItem] {
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        NotificationCenter.default.post(
                            name: .marmotBigFilesIntent, object: nil,
                            userInfo: ["minSizeMB": bigQuery.minSizeMB,
                                       "minAgeDays": bigQuery.minAgeDays])
                    }
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
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            NotificationCenter.default.post(
                                name: .marmotUninstallIntent, object: nil,
                                userInfo: ["appPath": app.id, "reset": reset])
                        }
                    })
            }
        }
        return items
    }

    // MARK: Drop overlay + freed toast

    /// Shown while an .app is being dragged over the window.
    private var dropOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.accent.opacity(0.08))
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Theme.accent.opacity(0.55),
                              style: StrokeStyle(lineWidth: 2.5, dash: [10, 7]))
            VStack(spacing: 10) {
                Image(systemName: "trash.square")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(Theme.accent)
                Text("Drop to uninstall")
                    .font(.title3.weight(.semibold))
                Text("Full removal preview first — nothing happens without your OK")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(14)
        .allowsHitTesting(false)
    }

    private func toastView(_ toast: FreedToast) -> some View {
        HStack(spacing: 12) {
            if let restored = toast.restoredMessage {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .foregroundStyle(.blue)
                Text(restored)
                    .font(.callout.weight(.medium))
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Freed \(ByteFormat.string(toast.freed))")
                    .font(.callout.weight(.semibold).monospacedDigit())
                if !toast.restorables.isEmpty {
                    Button("Undo") { undoToast(toast) }
                        .buttonStyle(.link)
                        .help("Moves everything from this clean back out of the Trash.")
                }
            }
            Button {
                withAnimation(.easeOut(duration: 0.2)) { self.toast = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.18)))
        .padding(.bottom, 16)
    }

    private func undoToast(_ current: FreedToast) {
        var restored = 0
        for result in current.restorables {
            guard let from = result.trashedTo else { continue }
            if TrashRestore.restore(target: result.item.target, from: from) == nil {
                restored += 1
            }
        }
        let text: String
        if restored == 0 {
            text = "Nothing could be restored — the Trash may have been emptied."
        } else {
            text = "Restored \(restored) item\(restored == 1 ? "" : "s") from the Trash."
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            toast = FreedToast(freed: current.freed, restoredMessage: text)
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack(spacing: 6) {
                Circle()
                    .fill(stats.snapshot.healthColor)
                    .frame(width: 8, height: 8)
                Text("Health \(stats.snapshot.healthScore)")
                    .font(.caption.weight(.medium))
                Spacer()
                Text("CPU \(Int(stats.snapshot.cpu.totalUsage))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
    }
}
