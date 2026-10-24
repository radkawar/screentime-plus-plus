import AppIntents
import ScreentimeCore

extension AppModel {
    /// The app delegate owns the model; Shortcuts never creates another monitor or store.
    static weak var shared: AppModel?

    static func forIntent() throws -> AppModel {
        guard let shared else { throw ScreentimeIntentError.unavailable }
        return shared
    }
}

private enum ScreentimeIntentError: LocalizedError {
    case unavailable
    case invalidMinutes
    case focusAlreadyRunning
    case noFocusRules
    case noFocus
    case lockedFocus
    case rulesCannotPause

    var errorDescription: String? {
        switch self {
        case .unavailable: "Open Screentime++ before running this shortcut."
        case .invalidMinutes: "Choose a positive number of minutes within the supported range."
        case .focusAlreadyRunning: "You already have a focus session running. Extend it in Screentime++."
        case .noFocusRules: "Add a Focus-only or enabled Pause rule in Screentime++ first."
        case .noFocus: "You don’t have a focus session running."
        case .lockedFocus: "Your focus session is locked and can’t be ended early."
        case .rulesCannotPause: "You can’t pause rules while your rules or focus session are locked."
        }
    }
}

struct StartFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Focus"
    static var description = IntentDescription("Block your default focus rules for a timed session.")
    static var openAppWhenRun = false

    @Parameter(title: "Minutes") var minutes: Int
    @Parameter(title: "Locked", default: false) var locked: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Start Focus for \(\.$minutes) minutes") { \.$locked }
    }

    init() {}

    init(minutes: Int, locked: Bool = false) {
        self.minutes = minutes
        self.locked = locked
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = try AppModel.forIntent()
        guard minutes > 0, minutes <= Int.max / 60 else { throw ScreentimeIntentError.invalidMinutes }
        guard model.activeFocus == nil else { throw ScreentimeIntentError.focusAlreadyRunning }
        let ruleIDs = model.defaultFocusRuleIDs
        guard !ruleIDs.isEmpty else { throw ScreentimeIntentError.noFocusRules }
        model.startFocus(minutes: minutes, ruleIDs: ruleIDs, locked: locked)
        return .result(dialog: "Your \(minutes)-minute focus session has started.")
    }
}

struct EndFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "End Focus"
    static var description = IntentDescription("End your current unlocked focus session.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = try AppModel.forIntent()
        guard let focus = model.activeFocus else { throw ScreentimeIntentError.noFocus }
        guard !focus.isLocked else { throw ScreentimeIntentError.lockedFocus }
        model.endFocus()
        return .result(dialog: "Your focus session has ended.")
    }
}

struct PauseRulesIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause Rules"
    static var description = IntentDescription("Temporarily pause your rules when no rules or focus lock applies.")
    static var openAppWhenRun = false

    @Parameter(title: "Minutes", default: 15) var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Pause rules for \(\.$minutes) minutes")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = try AppModel.forIntent()
        guard minutes > 0, minutes <= Int.max / 60 else { throw ScreentimeIntentError.invalidMinutes }
        guard model.canPauseRules else { throw ScreentimeIntentError.rulesCannotPause }
        model.pauseRules(minutes: minutes)
        return .result(dialog: "Your rules are paused for \(minutes) minutes.")
    }
}

struct TodaySummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "Today’s Summary"
    static var description = IntentDescription("Get your distracting time, daily goal, and total screen time today.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = try AppModel.forIntent()
        let (report, _) = await model.history(days: 1)
        let goal = TimeInterval(model.configuration.settings.dailyGoalMinutes) * 60
        let summary = "Today you spent \(Format.duration(report.distractingSeconds)) on distractions against a goal of \(Format.duration(goal)), and \(Format.duration(report.totalSeconds)) on screen in total."
        return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
    }
}

struct ScreentimeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartFocusIntent(), phrases: ["Start focus in \(.applicationName)"],
            shortTitle: "Start Focus", systemImageName: "moon")
        AppShortcut(
            intent: EndFocusIntent(), phrases: ["End focus in \(.applicationName)"],
            shortTitle: "End Focus", systemImageName: "moon.zzz")
        AppShortcut(
            intent: PauseRulesIntent(), phrases: ["Pause rules in \(.applicationName)"],
            shortTitle: "Pause Rules", systemImageName: "pause.circle")
        AppShortcut(
            intent: TodaySummaryIntent(), phrases: ["Show today’s summary in \(.applicationName)"],
            shortTitle: "Today’s Summary", systemImageName: "sun.max")
    }
}
