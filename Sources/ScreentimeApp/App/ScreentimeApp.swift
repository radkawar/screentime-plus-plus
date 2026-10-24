import AppKit
import ScreentimeCore
import Sparkle
import SwiftUI

@main
struct ScreentimeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Screentime++", id: "main") {
            MainShell()
                .environment(delegate.model)
                .frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 1_060, height: 720)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates\u{2026}") { delegate.updater.updater.checkForUpdates() }
            }
            NavigationCommands(model: delegate.model)
        }

        MenuBarExtra {
            MenuBarView().environment(delegate.model)
        } label: {
            MenuBarLabel(model: delegate.model)
        }
        .menuBarExtraStyle(.window)

        Window("This Week", id: "weekly-review") {
            WeeklyReviewSheet().environment(delegate.model)
        }
        .defaultSize(width: 680, height: 760)

        Window("Inspector", id: "inspector") {
            InspectorView().environment(delegate.model)
                .frame(minWidth: 680, minHeight: 480)
        }
        .defaultSize(width: 900, height: 640)

        Settings {
            SettingsView(updater: delegate.updater.updater).environment(delegate.model)
        }
        .windowResizability(.contentSize)
    }
}

private struct NavigationCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Rule from What’s in Front") { model.newRuleFromForeground() }
                .keyboardShortcut("n")
        }
        CommandGroup(after: .sidebar) {
            Button("Today") { model.navigate(to: .today) }.keyboardShortcut("1")
            Button("History") { model.navigate(to: .history) }.keyboardShortcut("2")
            Button("Rules") { model.navigate(to: .rules) }.keyboardShortcut("3")
            Button("Focus") { model.navigate(to: .focus) }.keyboardShortcut("4")
        }
        CommandGroup(after: .help) {
            Button("Inspector") {
                openWindow(id: "inspector")
                NSApp.activate()
            }
        }
    }
}

private struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let goal = TimeInterval(model.configuration.settings.dailyGoalMinutes) * 60
        let fraction = goal > 0 ? model.today.report.distractingSeconds / goal : 0
        HStack(spacing: Theme.Space.xs) {
            MenuBarRing(fraction: fraction)
            if let focus = model.activeFocus {
                Text(Format.countdown(focus.end.timeIntervalSince(model.now)))
                    .monospacedDigit()
                    .accessibilityLabel("Focus, \(Format.spokenDuration(focus.end.timeIntervalSince(model.now))) remaining")
            }
        }
        // The status item always exists, so it is where AppKit code (reopen
        // from Finder or Spotlight) gets a way to bring the main window back.
        .onAppear { model.openMainWindow = { openWindow(id: "main") } }
    }
}

enum Destination: String, Hashable, CaseIterable, Identifiable {
    case today
    case history
    case rules
    case focus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .history: "History"
        case .rules: "Rules"
        case .focus: "Focus"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .history: "chart.bar"
        case .rules: "hand.raised"
        case .focus: "moon"
        }
    }
}

struct MainShell: View {
    @Environment(AppModel.self) private var model
    @SceneStorage("destination") private var destination: Destination = .today
    @Environment(\.openWindow) private var openWindow
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Group {
            if model.configuration.settings.hasCompletedSetup {
                NavigationSplitView {
                    List(selection: Binding(get: { destination }, set: { if let value = $0 { destination = value } })) {
                        Section {
                            ForEach([Destination.today, .history]) { row($0) }
                            if [1, 2].contains(Calendar.current.component(.weekday, from: model.now)) {
                                Button {
                                    openWindow(id: "weekly-review")
                                } label: {
                                    Label("This Week", systemImage: "calendar")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Section("Control") {
                            ForEach([Destination.rules, .focus]) { row($0) }
                        }
                    }
                    .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
                    .safeAreaInset(edge: .bottom) { SidebarStatus() }
                } detail: {
                    detail
                }
            } else {
                SetupView()
            }
        }
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            applyNavigation()
        }
        .onChange(of: model.requestedDestination) { _, _ in applyNavigation() }
        .sheet(item: presentation) { item in
            switch item {
            case .draft(let rule):
                RuleEditor(rule: rule, isNew: true, undoManager: undoManager)
            case .edit(let rule):
                RuleEditor(rule: rule, isNew: false, undoManager: undoManager)
            case .detail(let subject): ItemDetailView(subject: subject)
            case .library:
                TemplatePicker { model.presentRuleDraft($0.make()) }
            }
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
        .overlay(alignment: .top) {
            if let problem = model.storageProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.caption)
                    .padding(Theme.Space.s)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, Theme.Space.s)
            }
        }
    }

    private enum Presentation: Identifiable {
        case draft(Rule), edit(Rule), detail(DraftSubject), library

        var id: String {
            switch self {
            case .draft(let rule): "draft:\(rule.id)"
            case .edit(let rule): "edit:\(rule.id)"
            case .detail(let subject): "detail:\(subject.bundleID):\(subject.domain ?? ""):\(subject.surface ?? "")"
            case .library: "library"
            }
        }
    }

    private var presentation: Binding<Presentation?> {
        Binding {
            if let rule = model.ruleDraft { return .draft(rule) }
            if let rule = model.editingRule { return .edit(rule) }
            if let subject = model.itemDetail { return .detail(subject) }
            if model.showsRuleLibrary { return .library }
            return nil
        } set: { value in
            if value == nil {
                model.ruleDraft = nil
                model.editingRule = nil
                model.itemDetail = nil
                model.showsRuleLibrary = false
            }
        }
    }

    private func applyNavigation() {
        guard let requested = model.requestedDestination else { return }
        destination = requested
        model.requestedDestination = nil
    }

    private func row(_ destination: Destination) -> some View {
        Label(destination.title, systemImage: destination.symbol).tag(destination)
    }

    @ViewBuilder
    private var detail: some View {
        switch destination {
        case .today: TodayView()
        case .history: HistoryView()
        case .rules: RulesView()
        case .focus: FocusView()
        }
    }
}

/// Bottom of the sidebar: what is happening now, in one line.
private struct SidebarStatus: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(Theme.Font.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .contentShape(Rectangle())
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.option) { openWindow(id: "inspector") }
        }
        .help("Option-click to open Inspector")
        .accessibilityAction(named: "Open Inspector") { openWindow(id: "inspector") }
        .accessibilityElement(children: .combine)
    }

    private var text: String {
        if !model.isAccessibilityTrusted { return "Needs Accessibility" }
        if let focus = model.activeFocus { return "Focus until \(Format.clock(focus.end))" }
        switch model.live.status {
        case .idle: return "Idle"
        case .away: return "Away"
        default:
            let count = model.configuration.rules.filter(\.isEnabled).count
            return "Watching \u{00B7} \(count) rule\(count == 1 ? "" : "s") on"
        }
    }

    private var color: Color {
        if !model.isAccessibilityTrusted { return Theme.caution }
        if model.activeFocus != nil { return Theme.accent }
        switch model.live.status {
        case .idle, .away: return .secondary
        default: return Theme.accent
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel = {
        FocusKeepaliveAgent.exitIfAlreadyRunning()
        return AppModel()
    }()
    let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    override init() {
        super.init()
        AppModel.shared = model
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme == "screentimepp", url.host == "today" {
                model.navigate(to: .today)
            } else {
                RulePackFiles.open(url, model: model)
            }
        }
    }

    /// Opening Screentime++ again (Finder, Spotlight, Dock) shows the main window
    /// even when it was closed and only the menu bar item remained.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            model.openMainWindow?()
            NSApp.activate()
        }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
            QAGallery.presentIfRequested(model: model, updater: updater.updater)
        #endif
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let focus = model.activeFocus, focus.isLocked, !Self.isSystemShutdown else {
            model.flush()
            return .terminateNow
        }
        let alert = NSAlert()
        alert.messageText = "Focus is locked until \(Format.clock(focus.end))"
        alert.informativeText = "Screentime++ keeps running until the session ends."
        alert.addButton(withTitle: "OK")
        alert.runModal()
        return .terminateCancel
    }

    /// Logging out, restarting or shutting down must never be blocked.
    private static var isSystemShutdown: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
            let reason = event.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.enumCodeValue
        else { return false }
        return [kAEShutDown, kAERestart, kAEReallyLogOut, kAELogOut].map { OSType($0) }.contains(reason)
    }
}
