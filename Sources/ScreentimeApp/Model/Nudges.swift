import Foundation
import ScreentimeCore

/// Quiet in-app reminders: no notification permission, sound, or interaction.
@MainActor
final class Nudges {
    private var time = TimeNudgeTracker()
    private var ending = SessionEndingNudgeTracker()
    private var grantSubjects: [UUID: String] = [:]

    func handle(_ sample: MonitorSample, model: AppModel) {
        let settings = model.configuration.settings
        let grants = model.configuration.grants
        if grantSubjects.keys.contains(where: { id in !grants.contains { $0.ruleID == id } }) {
            grantSubjects = grantSubjects.filter { id, _ in grants.contains { $0.ruleID == id } }
        }
        let shielded = model.shields.active != nil
        let focusBlocked: Bool
        if model.rulesPausedUntil == nil, case .block(let block) = model.live.evaluation.intervention, case .focus = block.reason {
            focusBlocked = true
        } else {
            focusBlocked = false
        }
        let suppressed = shielded || focusBlocked
        let threshold = TimeInterval(max(30, settings.idleThresholdSeconds))
        var elapsedMinutes: Int?
        var currentTitle: String?
        var canShow = false

        switch sample.state {
        case .active(let reading):
            guard model.isAccessibilityTrusted, reading.isComplete else {
                _ = time.record(subject: nil, at: sample.date, idleThreshold: threshold)
                return
            }
            let context = reading.context
            let title = context.domain ?? context.appName
            currentTitle = title
            canShow = !suppressed
            for match in model.live.evaluation.matches where grants.contains(where: { $0.ruleID == match.rule.id }) {
                if grantSubjects[match.rule.id] == nil { grantSubjects[match.rule.id] = title }
            }
            let eligible = settings.timeNudgesEnabled != false
                && (settings.timeNudgesForEverything == true || !model.live.evaluation.matches.isEmpty)
            elapsedMinutes = time.record(
                subject: context.subject, at: sample.date, idleThreshold: threshold,
                cadence: settings.timeNudgeCadence ?? .tenTwentyThirty,
                isSuppressed: suppressed || !eligible)
        case .away:
            _ = time.record(subject: nil, at: sample.date, idleThreshold: threshold)
        case .idle:
            // The monitor has already applied the user's idle policy.
            time.reset()
        case .own:
            time.reset()
            canShow = !suppressed
        }

        if let grant = ending.reminder(grants: grants, at: sample.date, isSuppressed: !canShow) {
            let title = grantSubjects[grant.ruleID]
                ?? model.configuration.rules.first(where: { $0.id == grant.ruleID })?.name
                ?? "your session"
            Toast.show(title: "2 minutes left on \(title)", detail: "Your pause returns when this session ends.", symbol: "hourglass")
        } else if let elapsedMinutes, let currentTitle {
            Toast.show(title: "\(elapsedMinutes) minutes on \(currentTitle)", detail: "Time in this visit", symbol: "clock")
        }
    }
}
