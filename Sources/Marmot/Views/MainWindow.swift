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

struct MainWindow: View {
    // Internal (not private) so MainWindow+Palette can drive navigation.
    @State var selection: SidebarSection?
    @State var showPalette = false
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
            if dropTargeted { DropTargetOverlay() }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                FreedToastView(
                    toast: toast,
                    onUndo: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            self.toast = toast.performUndo()
                        }
                    },
                    onClose: {
                        withAnimation(.easeOut(duration: 0.2)) { self.toast = nil }
                    })
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
            DeepLink.post(.marmotUninstallIntent,
                          userInfo: ["appPath": path, "reset": false], delay: 0.2)
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
