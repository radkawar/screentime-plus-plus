import AppKit
import Observation
import OSLog
import ScreentimeCore
import ServiceManagement
import SwiftUI

private let log = Logger(subsystem: "dev.screentimepp.app", category: "model")

/// What the engine sees right now; drives the Inspector and the menu bar.
struct LiveState {
    enum Status: Equatable {
        case starting
        case active
        case idle
        case away
        case own
        case needsAccessibility
    }

    var status: Status = .starting
    var context: ForegroundContext?
    var content: PageContent?
    var evaluation: Evaluation = .none
    var sampledAt: Date?
}

struct TodaySummary {
    var report: UsageReport
    var interventions: [InterventionRecord]
    var streakDays: Int

    static func empty(now: Date) -> TodaySummary {
        let start = Calendar.current.startOfDay(for: now)
        return TodaySummary(
            report: UsageReport(segments: [], interval: DateInterval(start: start, end: now)), interventions: [],
            streakDays: 0)
    }

    var turnedBack: Int {
        interventions.filter { $0.outcome == .turnedBack || $0.outcome == .closed }.count
    }
}

@MainActor
@Observable
final class AppModel {
    private(set) var configuration: AppConfiguration
    private(set) var live = LiveState()
    private(set) var today: TodaySummary
    private(set) var now = Date()
    private(set) var storageProblem: String?
    private(set) var isAccessibilityTrusted = AccessibilityPermission.isTrusted

    @ObservationIgnored let store: UsageStore?
    @ObservationIgnored private let configStore: ConfigStore?
    @ObservationIgnored private let tracker: UsageTracker?
    @ObservationIgnored private let monitor = ActivityMonitor()
    @ObservationIgnored let shields = ShieldCoordinator()
    @ObservationIgnored private var lastReload = Date.distantPast
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    /// Mirrors the coordinator so views can observe it.
    private(set) var shieldPresentation: ShieldPresentation?

    init() {
        var problem: String?
        var store: UsageStore?
        var configStore: ConfigStore?
        var configuration = AppConfiguration.starter
        do {
            let url = try UsageStore.defaultURL()
            store = try UsageStore(path: url.path)
            let config = ConfigStore(url: try ConfigStore.defaultURL())
            configStore = config
            if let saved = try config.load() { configuration = saved }
        } catch {
            problem = "Screentime++ can\u{2019}t open its data folder. History won\u{2019}t be saved. (\(error))"
            log.error("storage failed: \(String(describing: error), privacy: .public)")
        }
        self.store = store
        self.configStore = configStore
        self.configuration = configuration
        self.storageProblem = problem
        self.tracker = store.map { UsageTracker(store: $0) }
        self.today = .empty(now: Date())

        try? store?.prune(before: Date().addingTimeInterval(-TimeInterval(configuration.settings.retentionDays) * 86_400))
        shields.parksTabs = configuration.settings.parksBrowserTabs
        shields.onPresent = { [weak self] presentation, context in
            self?.logPresented(presentation, context: context)
        }
        shields.onResolve = { [weak self] active, resolution in
            self?.handleResolution(active, resolution)
        }
        shields.onTrack = { [weak self] pid in self?.monitor.trackWindow(pid: pid) }
        monitor.onSample = { [weak self] sample in self?.handle(sample) }
        monitor.onWindowFrame = { [weak self] pid, frame in self?.shields.windowMoved(pid: pid, frame: frame) }
        applyMonitorConfiguration()
        monitor.start()
        reloadToday()
    }

    // MARK: Sampling

    private func handle(_ sample: MonitorSample) {
        now = sample.date
        isAccessibilityTrusted = AccessibilityPermission.isTrusted
        pruneExpired(now: sample.date)
        live.sampledAt = sample.date

        switch sample.state {
        case .active(let reading):
            let context = reading.context
            live.context = context
            live.content = sample.content
            guard isAccessibilityTrusted else {
                live.status = .needsAccessibility
                tracker?.record(context: context, matches: [], isShielded: false, at: sample.date)
                break
            }
            live.status = .active
            if !reading.isComplete, let active = shields.active, active.pid == context.pid {
                // A slow AX answer is not evidence the page changed. Keep the shield.
                tracker?.record(context: context, matches: [], isShielded: true, at: sample.date)
                break
            }
            let evaluation = PolicyEngine.evaluate(
                context: context, content: sample.content, rules: rulesPausedUntil == nil ? configuration.rules : [],
                runtime: runtime,
                now: sample.date)
            live.evaluation = evaluation
            shields.update(intervention: evaluation.intervention, reading: reading, now: sample.date)
            tracker?.record(
                context: context, matches: evaluation.matches, isShielded: shields.active != nil, at: sample.date)
        case .own:
            live.status = .own
            shields.foregroundLeft()
            tracker?.record(context: nil, matches: [], isShielded: false, at: sample.date)
        case .idle:
            live.status = .idle
            tracker?.record(context: nil, matches: [], isShielded: false, at: sample.date)
        case .away:
            live.status = .away
            shields.foregroundLeft()
            tracker?.record(context: nil, matches: [], isShielded: false, at: sample.date)
        }
        shieldPresentation = shields.presentation
        if sample.date.timeIntervalSince(lastReload) >= 30 { reloadToday() }
    }

    var runtime: RuleRuntime {
        let usage = tracker?.ruleUsage ?? [:]
        return RuleRuntime(
            usageSeconds: usage.mapValues(\.seconds), opens: usage.mapValues(\.opens),
            grants: configuration.grants, focus: configuration.focus)
    }

    func usage(for rule: Rule) -> RuleDayUsage {
        tracker?.ruleUsage[rule.id] ?? RuleDayUsage()
    }

    private func pruneExpired(now: Date) {
        var config = configuration
        var changed = false
        if config.grants.contains(where: { $0.until <= now }) {
            config.grants.removeAll { $0.until <= now }
            changed = true
        }
        if let focus = config.focus, focus.end <= now {
            config.focus = nil
            changed = true
        }
        if let lock = config.settings.rulesLockedUntil, lock <= now {
            config.settings.rulesLockedUntil = nil
            changed = true
        }
        if let paused = config.settings.rulesPausedUntil, paused <= now {
            config.settings.rulesPausedUntil = nil
            changed = true
        }
        if changed { commit(config) }
    }

    // MARK: Shield outcomes

    private func logPresented(_ presentation: ShieldPresentation, context: ForegroundContext) -> Int64? {
        let kind: InterventionKind
        switch presentation.intervention {
        case .pause: kind = .pause
        case .block(let block):
            switch block.reason {
            case .focus: kind = .focus
            case .minutesLimit, .opensLimit: kind = .limit
            case .rule: kind = .block
            }
        }
        let record = InterventionRecord(
            at: presentation.shownAt, ruleID: presentation.rule.id, ruleName: presentation.rule.name, kind: kind,
            subject: context.domain ?? context.appName, outcome: .shown)
        return try? store?.insert(record)
    }

    private func handleResolution(_ active: ShieldCoordinator.Active, _ resolution: ShieldResolution) {
        let at = Date()
        var config = configuration
        let intention = active.presentation.intention.trimmingCharacters(in: .whitespacesAndNewlines)
        let outcome: InterventionOutcome
        switch resolution {
        case .continued(let minutes):
            config.grants.append(
                AccessGrant(ruleID: active.ruleID, until: at.addingTimeInterval(TimeInterval(minutes * 60)), kind: .session))
            tracker?.registerOpen(ruleID: active.ruleID, at: at)
            outcome = .continued
        case .overridden:
            config.grants.append(AccessGrant(ruleID: active.ruleID, until: at.addingTimeInterval(60), kind: .override))
            outcome = .overridden
        case .turnedBack:
            outcome = .turnedBack
        case .declined:
            outcome = .turnedBack
            let count = today.turnedBack + 1
            Toast.show(
                title: "Turned back", detail: count == 1 ? "First time today" : "\(count) times today",
                symbol: "arrow.uturn.backward")
        case .closedAutomatically:
            outcome = .closed
        case .released:
            // A global pause is a deliberate bypass, recorded like an override.
            outcome = .overridden
        }
        if config != configuration { commit(config) }
        if let id = active.recordID {
            try? store?.update(interventionID: id, outcome: outcome, intention: intention.isEmpty ? nil : intention)
        }
        shieldPresentation = shields.presentation
        reloadToday()
        monitor.refresh()
    }

    // MARK: Reports

    func reloadToday() {
        lastReload = Date()
        guard let store else { return }
        tracker?.flush()
        let goal = TimeInterval(configuration.settings.dailyGoalMinutes * 60)
        reloadTask?.cancel()
        reloadTask = Task.detached(priority: .utility) { [weak self] in
            let calendar = Calendar.current
            let now = Date()
            let start = calendar.startOfDay(for: now)
            let interval = DateInterval(start: start, end: max(now, start.addingTimeInterval(1)))
            let segments = (try? store.segments(in: interval)) ?? []
            let interventions = (try? store.interventions(in: interval)) ?? []
            let streak = Self.streak(store: store, goal: goal, now: now, calendar: calendar)
            let summary = TodaySummary(
                report: UsageReport(segments: segments, interval: interval), interventions: interventions,
                streakDays: streak)
            await MainActor.run { [weak self] in
                guard !Task.isCancelled else { return }
                self?.today = summary
            }
        }
    }

    /// Consecutive days, ending today if today is still under goal, with
    /// distracting time within the goal and no overrides.
    nonisolated static func streak(store: UsageStore, goal: TimeInterval, now: Date, calendar: Calendar) -> Int {
        let todayStart = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -60, to: todayStart) else { return 0 }
        let interval = DateInterval(start: windowStart, end: max(now, todayStart.addingTimeInterval(1)))
        guard let segments = try? store.segments(in: interval),
            let interventions = try? store.interventions(in: interval), !segments.isEmpty
        else { return 0 }
        let days = UsageReport(segments: segments, interval: interval).daily(calendar: calendar)
        let overriddenDays = Set(
            interventions.filter { $0.outcome == .overridden }.map { calendar.startOfDay(for: $0.at) })
        let firstDay = segments.first.map { calendar.startOfDay(for: $0.start) } ?? todayStart
        var streak = 0
        for day in days.reversed() where day.day >= firstDay {
            let good = day.distractingSeconds <= goal && !overriddenDays.contains(day.day)
            if good {
                streak += 1
            } else if day.day == todayStart {
                continue
            } else {
                break
            }
        }
        return streak
    }

    func history(days: Int) async -> (UsageReport, [InterventionRecord]) {
        guard let store else {
            return (UsageReport(segments: [], interval: DateInterval(start: Date(), duration: 1)), [])
        }
        tracker?.flush()
        return await Task.detached(priority: .userInitiated) {
            let calendar = Calendar.current
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
            let start = calendar.date(byAdding: .day, value: -days, to: end)!
            let interval = DateInterval(start: start, end: end)
            let segments = (try? store.segments(in: interval)) ?? []
            let interventions = (try? store.interventions(in: interval)) ?? []
            return (UsageReport(segments: segments, interval: interval), interventions)
        }.value
    }

    // MARK: Configuration

    var rulesLocked: Bool { configuration.settings.rulesAreLocked(at: now) }

    var activeFocus: FocusSession? {
        configuration.focus.flatMap { $0.isActive(at: now) ? $0 : nil }
    }

    func canEdit(_ rule: Rule) -> Bool {
        guard !rulesLocked else { return false }
        if let focus = activeFocus, focus.isLocked, focus.ruleIDs.contains(rule.id) { return false }
        return true
    }

    func save(rule: Rule) {
        var config = configuration
        if let index = config.rules.firstIndex(where: { $0.id == rule.id }) {
            guard canEdit(config.rules[index]) else { return }
            config.rules[index] = rule
        } else {
            config.rules.append(rule)
        }
        commit(config)
    }

    func delete(rule: Rule) {
        guard canEdit(rule) else { return }
        var config = configuration
        config.rules.removeAll { $0.id == rule.id }
        config.grants.removeAll { $0.ruleID == rule.id }
        commit(config)
    }

    func setEnabled(_ enabled: Bool, rule: Rule) {
        guard canEdit(rule) else { return }
        var updated = rule
        updated.isEnabled = enabled
        save(rule: updated)
    }

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        var config = configuration
        change(&config.settings)
        commit(config)
    }

    func lockRules(until date: Date) {
        updateSettings {
            $0.rulesLockedUntil = max(date, $0.rulesLockedUntil ?? date)
            // A lock means rules apply: it ends any pause.
            $0.rulesPausedUntil = nil
        }
    }

    /// What Focus blocks unless you choose otherwise: the Focus-only rules and
    /// every enabled pause rule. Time-of-day blocks keep their own schedule.
    var defaultFocusRuleIDs: [UUID] {
        configuration.rules.filter { rule in
            if case .duringFocus = rule.schedule { return true }
            if case .pause = rule.response { return rule.isEnabled }
            return false
        }.map(\.id)
    }

    func startFocus(minutes: Int, ruleIDs: [UUID], locked: Bool, title: String = "Focus") {
        guard activeFocus == nil, !ruleIDs.isEmpty else { return }
        var config = configuration
        let start = Date()
        config.focus = FocusSession(
            title: title, start: start, end: start.addingTimeInterval(TimeInterval(minutes * 60)), ruleIDs: ruleIDs,
            isLocked: locked)
        // A new focus session supersedes running pause sessions for its rules.
        config.grants.removeAll { ruleIDs.contains($0.ruleID) }
        // Choosing to focus ends any pause of the rules.
        config.settings.rulesPausedUntil = nil
        commit(config)
    }

    func endFocus() {
        guard let focus = activeFocus, !focus.isLocked else { return }
        var config = configuration
        config.focus = nil
        commit(config)
    }

    func completeSetup(templates: [RuleTemplate], goalMinutes: Int) {
        var config = configuration
        if !config.settings.hasCompletedSetup {
            let chosen = templates.map { $0.make() }
            let hasFocusRule = chosen.contains { if case .duringFocus = $0.schedule { return true } else { return false } }
            config.rules = chosen + (hasFocusRule ? [] : [RuleTemplate.focusBlocklist.make()])
        }
        config.settings.dailyGoalMinutes = goalMinutes
        config.settings.hasCompletedSetup = true
        commit(config)
    }

    /// Adds every rule in a pack, skipping ones already added from the same template name.
    func add(pack: RulePack) {
        var config = configuration
        let existing = Set(config.rules.map(\.name))
        config.rules += pack.templates.map { $0.make() }.filter { !existing.contains($0.name) }
        commit(config)
    }

    /// Safety valve: suspend every rule for a while. Unavailable while a lock applies.
    var canPauseRules: Bool {
        !rulesLocked && !(activeFocus?.isLocked ?? false)
    }

    var rulesPausedUntil: Date? {
        configuration.settings.rulesPausedUntil.flatMap { $0 > now ? $0 : nil }
    }

    func pauseRules(minutes: Int) {
        guard canPauseRules else { return }
        updateSettings { $0.rulesPausedUntil = Date().addingTimeInterval(TimeInterval(minutes * 60)) }
        shields.release()
    }

    func resumeRules() {
        updateSettings { $0.rulesPausedUntil = nil }
    }

    func deleteHistory() {
        try? store?.deleteAll()
        reloadToday()
    }

    private func commit(_ config: AppConfiguration) {
        configuration = config
        do {
            try configStore?.save(config)
        } catch {
            storageProblem = "Your rules couldn\u{2019}t be saved. (\(error.localizedDescription))"
        }
        shields.parksTabs = config.settings.parksBrowserTabs
        applyMonitorConfiguration()
        monitor.refresh()
    }

    private func applyMonitorConfiguration() {
        let settings = configuration.settings
        let needsText = settings.inspectsPageText && configuration.rules.contains { $0.isEnabled && $0.needsPageText }
        monitor.configure(
            needsContent: needsText || isInspectorOpen, idleThreshold: TimeInterval(settings.idleThresholdSeconds))
    }

    /// While the Inspector is visible, read page text even without content rules.
    var isInspectorOpen = false {
        didSet { applyMonitorConfiguration() }
    }

    /// Opens the main window; provided by the always-present menu bar label.
    @ObservationIgnored var openMainWindow: (() -> Void)?

    func requestAccessibility() {
        AccessibilityPermission.request()
    }

    func refreshNow() {
        isAccessibilityTrusted = AccessibilityPermission.isTrusted
        monitor.refresh()
    }

    func flush() {
        tracker?.flush()
    }

    // MARK: Launch at login

    var launchesAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                storageProblem = "Login item couldn\u{2019}t be changed: \(error.localizedDescription)"
            }
        }
    }
}
