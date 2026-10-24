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
                .tint(Theme.ember)
        }
        .defaultSize(width: 1_060, height: 720)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates\u{2026}") { delegate.updater.updater.checkForUpdates() }
            }
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarView().environment(delegate.model)
        } label: {
            MenuBarLabel(model: delegate.model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(updater: delegate.updater.updater).environment(delegate.model)
        }
    }
}

private struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        if let focus = model.activeFocus {
            Label(Format.countdown(focus.end.timeIntervalSince(model.now)), systemImage: "moon.fill")
                .labelStyle(.titleAndIcon)
                .monospacedDigit()
        } else {
            Image(systemName: model.shieldPresentation == nil ? "hourglass" : "hourglass.tophalf.filled")
                .accessibilityLabel("Screentime++")
        }
    }
}

enum Destination: String, Hashable, CaseIterable, Identifiable {
    case today
    case history
    case rules
    case focus
    case inspector

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .history: "History"
        case .rules: "Rules"
        case .focus: "Focus"
        case .inspector: "Inspector"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .history: "chart.bar"
        case .rules: "hand.raised"
        case .focus: "moon"
        case .inspector: "text.magnifyingglass"
        }
    }
}

struct MainShell: View {
    @Environment(AppModel.self) private var model
    @SceneStorage("destination") private var destination: Destination = .today

    var body: some View {
        Group {
            if model.configuration.settings.hasCompletedSetup {
                NavigationSplitView {
                    List(selection: Binding(get: { destination }, set: { if let value = $0 { destination = value } })) {
                        Section {
                            ForEach([Destination.today, .history]) { row($0) }
                        }
                        Section("Control") {
                            ForEach([Destination.rules, .focus]) { row($0) }
                        }
                        Section("Diagnostics") {
                            row(.inspector)
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
        .onAppear { NSApp.setActivationPolicy(.regular) }
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
        case .inspector: InspectorView()
        }
    }
}

/// Bottom of the sidebar: what is happening now, in one line.
private struct SidebarStatus: View {
    @Environment(AppModel.self) private var model

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
        .accessibilityElement(children: .combine)
    }

    private var text: String {
        if let focus = model.activeFocus { return "Focus until \(Format.clock(focus.end))" }
        switch model.live.status {
        case .needsAccessibility: return "Needs Accessibility"
        case .idle: return "Idle"
        case .away: return "Away"
        default:
            let count = model.configuration.rules.filter(\.isEnabled).count
            return "Watching \u{00B7} \(count) rule\(count == 1 ? "" : "s") on"
        }
    }

    private var color: Color {
        if model.activeFocus != nil { return Theme.ember }
        switch model.live.status {
        case .needsAccessibility: return Theme.ember
        case .idle, .away: return .secondary
        default: return Theme.color(for: .productivity)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

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
