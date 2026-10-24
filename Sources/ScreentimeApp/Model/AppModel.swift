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
    var itemDetail: DraftSubject?
    var itemDetailInterval: DateInterval?
    let focusCalendar = FocusCalendar()

    @ObservationIgnored let store: UsageStore?
    @ObservationIgnored private let configStore: ConfigStore?
    @ObservationIgnored private let tracker: UsageTracker?
    @ObservationIgnored private let monitor = ActivityMonitor()
    @ObservationIgnored let shields = ShieldCoordinator()
    @ObservationIgnored let notifications = Notifications()
    @ObservationIgnored private let nudges = Nudges()
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
        notifications.reconcile(configuration: configuration, today: today)
        FocusKeepaliveAgent.shared.synchronize(focus: configuration.focus)
    }

    // MARK: Sampling

    private func handle(_ sample: MonitorSample) {
        now = sample.date
        isAccessibilityTrusted = AccessibilityPermission.isTrusted
        pruneExpired(now: sample.date)
        reconcileFocusAutomation(at: sample.date)
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
        nudges.handle(sample, model: self)
        if sample.date.timeIntervalSince(lastReload) >= 30 { reloadToday() }
    }

    var runtime: RuleRuntime {
        let usage = tracker?.ruleUsage ?? [:]
        return RuleRuntime(
            usageSeconds: usage.mapValues(\.seconds), opens: usage.mapValues(\.opens),
            grants: configuration.grants, focus: rulesPausedUntil == nil ? configuration.focus : nil)
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
                if let self {
                    self.notifications.reconcile(configuration: self.configuration, today: summary)
                    WidgetPublisher.publish(
                        report: summary.report,
                        goalSeconds: TimeInterval(self.configuration.settings.dailyGoalMinutes * 60))
                }
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

    func presentItemDetail(_ subject: DraftSubject) {
        presentItemDetail(subject, in: nil)
    }

    func presentItemDetail(_ subject: DraftSubject, in interval: DateInterval?) {
        ruleDraft = nil
        editingRule = nil
        showsRuleLibrary = false
        itemDetailInterval = interval
        itemDetail = subject
        openMainWindow?()
        NSApp.activate()
    }

    func history(in interval: DateInterval) async -> (UsageReport, [InterventionRecord]) {
        guard let store else { return (UsageReport(segments: [], interval: interval), []) }
        tracker?.flush()
        return await Task.detached(priority: .userInitiated) {
            let segments = (try? store.segments(in: interval)) ?? []
            let interventions = (try? store.interventions(in: interval)) ?? []
            return (UsageReport(segments: segments, interval: interval), interventions)
        }.value
    }

    func history(on day: Date) async -> TodaySummary {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        let (report, interventions) = await history(in: DateInterval(start: start, end: end))
        return TodaySummary(report: report, interventions: interventions, streakDays: 0)
    }

    func history(for subject: DraftSubject, in interval: DateInterval) async -> UsageReport {
        let (report, _) = await history(in: interval)
        return report.filtered(for: subject)
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

    func delete(rule: Rule, undoManager: UndoManager? = nil) {
        guard let index = configuration.rules.firstIndex(where: { $0.id == rule.id }),
            canEdit(configuration.rules[index])
        else { return }
        let original = configuration.rules[index]
        let grants = configuration.grants.filter { $0.ruleID == original.id }
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] model in
            model.restoreDeletedRule(original, at: index, grants: grants, undoManager: undoManager)
        }
        undoManager?.setActionName("Delete Rule")
        var config = configuration
        config.rules.remove(at: index)
        config.grants.removeAll { $0.ruleID == original.id }
        commit(config)
        Toast.show(
            title: "Deleted “\(original.name)”",
            detail: undoManager == nil ? "Its history stays in History." : "⌘Z to undo",
            symbol: "arrow.uturn.backward")
    }

    private func restoreDeletedRule(_ rule: Rule, at index: Int, grants: [AccessGrant], undoManager: UndoManager?) {
        guard canEdit(rule), !configuration.rules.contains(where: { $0.id == rule.id }) else { return }
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] model in
            model.delete(rule: rule, undoManager: undoManager)
        }
        undoManager?.setActionName("Delete Rule")
        var config = configuration
        config.rules.insert(rule, at: min(index, config.rules.count))
        config.grants.append(contentsOf: grants.filter { $0.until > now })
        commit(config)
    }

    func setEnabled(_ enabled: Bool, rule: Rule, undoManager: UndoManager? = nil) {
        guard let original = configuration.rules.first(where: { $0.id == rule.id }),
            canEdit(original), original.isEnabled != enabled
        else { return }
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] model in
            model.setEnabled(original.isEnabled, rule: original, undoManager: undoManager)
        }
        undoManager?.setActionName(enabled ? "Enable Rule" : "Disable Rule")
        var updated = original
        updated.isEnabled = enabled
        save(rule: updated)
        Toast.show(
            title: "\(enabled ? "Enabled" : "Disabled") “\(original.name)”",
            detail: undoManager == nil ? "" : "⌘Z to undo", symbol: "arrow.uturn.backward")
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

    func startFocus(minutes: Int, ruleIDs: [UUID], locked: Bool, title: String = "Focus",
                    categories: [UsageCategory] = [], targets: [Target] = []) {
        startFocus(profile: FocusProfile(name: title, minutes: minutes, isLocked: locked,
                                       categories: categories, targets: targets, ruleIDs: ruleIDs))
    }

    var focusProfiles: [FocusProfile] { configuration.focusProfiles ?? [] }

    var defaultFocusProfile: FocusProfile {
        focusProfiles.first { $0.id == configuration.defaultFocusProfileID }
            ?? focusProfiles.first ?? FocusProfile(name: "Focus")
    }

    func saveFocusProfile(_ profile: FocusProfile, makeDefault: Bool = false) {
        var config = configuration
        var profiles = config.focusProfiles ?? []
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            profiles[index].consumedOccurrences = config.focusProfiles?[index].consumedOccurrences
        } else {
            profiles.append(profile)
        }
        config.focusProfiles = profiles
        if makeDefault || config.defaultFocusProfileID == nil { config.defaultFocusProfileID = profile.id }
        commit(config)
    }

    func deleteFocusProfile(_ profile: FocusProfile) {
        var config = configuration
        config.focusProfiles?.removeAll { $0.id == profile.id }
        if config.defaultFocusProfileID == profile.id { config.defaultFocusProfileID = config.focusProfiles?.first?.id }
        commit(config)
    }

    func startFocus(profile: FocusProfile, minutes: Int? = nil, locked: Bool? = nil) {
        guard activeFocus == nil, profile.hasSelection, (minutes ?? profile.minutes) > 0 else { return }
        var chosen = profile
        chosen.minutes = minutes ?? profile.minutes
        chosen.isLocked = locked ?? profile.isLocked
        var config = configuration
        config.focus = chosen.session(start: Date())
        config.grants.removeAll { chosen.ruleIDs.contains($0.ruleID) }
        config.settings.rulesPausedUntil = nil
        commit(config)
    }

    private func reconcileFocusAutomation(at date: Date) {
        let events = focusCalendar.occurrences(profiles: focusProfiles, now: date)
        let decision = FocusAutomation.decision(profiles: focusProfiles, current: configuration.focus,
                                                events: events, now: date)
        var config = configuration
        switch decision {
        case .none: return
        case .stop: config.focus = nil
        case .updateEnd(let end):
            config.focus?.end = end
            if let occurrenceID = config.focus?.automationID,
               let index = config.focusProfiles?.firstIndex(where: { $0.consumedOccurrences?[occurrenceID] != nil }) {
                config.focusProfiles?[index].consumedOccurrences?[occurrenceID] = end
            }
        case .start(let profileID, let occurrenceID, let end):
            guard let index = config.focusProfiles?.firstIndex(where: { $0.id == profileID }),
                  let profile = config.focusProfiles?[index] else { return }
            config.focus = profile.session(start: date, end: end, automationID: occurrenceID)
            var consumed = profile.consumedOccurrences?.filter { $0.value > date } ?? [:]
            consumed[occurrenceID] = end
            config.focusProfiles?[index].consumedOccurrences = consumed
            config.grants.removeAll { profile.ruleIDs.contains($0.ruleID) }
            config.settings.rulesPausedUntil = nil
        }
        commit(config)
    }

    func endFocus() {
        guard let focus = activeFocus, !focus.isLocked else { return }
        var config = configuration
        config.focus = nil
        commit(config)
    }

    /// Adding time only tightens a session, so locked sessions can be extended too.
    func extendFocus(minutes: Int) {
        guard minutes > 0, var focus = activeFocus, focus.isActive(at: Date()) else { return }
        focus.end = focus.end.addingTimeInterval(TimeInterval(minutes) * 60)
        // An explicit extension takes over from the automatic end time.
        focus.automationID = nil
        var config = configuration
        config.focus = focus
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
        notifications.reconcile(configuration: config, today: today)
        do {
            try configStore?.save(config)
            FocusKeepaliveAgent.shared.synchronize(focus: config.focus)
        } catch {
            storageProblem = "Your rules couldn\u{2019}t be saved. (\(error.localizedDescription))"
        }
        shields.parksTabs = config.settings.parksBrowserTabs
        applyMonitorConfiguration()
        monitor.refresh()
    }

    private func applyMonitorConfiguration() {
        let settings = configuration.settings
        let needsText = settings.inspectsPageText
            && (configuration.rules.contains { $0.isEnabled && $0.needsPageText }
                || (configuration.focus?.targets?.contains(where: \.needsPageText) ?? false))
        monitor.configure(
            needsContent: needsText || isInspectorOpen, idleThreshold: TimeInterval(settings.idleThresholdSeconds),
            appIdleOverrides: settings.appIdleOverrides ?? [:])
    }

    /// While the Inspector is visible, read page text even without content rules.
    var isInspectorOpen = false {
        didSet { applyMonitorConfiguration() }
    }

    /// Opens the main window; provided by the always-present menu bar label.
    @ObservationIgnored var openMainWindow: (() -> Void)?

    var ruleDraft: Rule?
    var editingRule: Rule?
    var requestedDestination: Destination?
    var showsRuleLibrary = false

    func navigate(to destination: Destination) {
        requestedDestination = destination
        openMainWindow?()
        NSApp.activate()
    }

    func presentRuleDraft(_ rule: Rule) {
        itemDetail = nil
        editingRule = nil
        showsRuleLibrary = false
        ruleDraft = rule
        navigate(to: .rules)
    }

    func editRule(id: UUID) {
        guard let rule = configuration.rules.first(where: { $0.id == id }) else { return }
        itemDetail = nil
        ruleDraft = nil
        showsRuleLibrary = false
        editingRule = rule
        navigate(to: .rules)
    }

    func newRuleFromForeground() {
        if let context = live.context, !context.bundleID.isEmpty,
            context.bundleID != Bundle.main.bundleIdentifier
        {
            presentRuleDraft(RuleDraft.rule(for: DraftSubject(context: context), kind: .pause))
        } else {
            itemDetail = nil
            ruleDraft = nil
            editingRule = nil
            showsRuleLibrary = true
            navigate(to: .rules)
        }
    }

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
