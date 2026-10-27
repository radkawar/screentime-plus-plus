import ScreentimeCore
import SwiftUI

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let report = model.today.report
        let goal = TimeInterval(model.configuration.settings.dailyGoalMinutes * 60)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Format.duration(report.distractingSeconds, showSeconds: true))
                        .font(Theme.Font.display(30))
                        .monospacedDigit()
                    Text("distracting \u{00B7} goal \(Format.duration(goal)) \u{00B7} \(Format.duration(report.totalSeconds)) on screen")
                        .font(Theme.Font.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                if model.today.streakDays > 0 {
                    Label("\(model.today.streakDays)", systemImage: "flame")
                        .font(Theme.Font.label)
                        .foregroundStyle(Theme.accent)
                        .help("\(model.today.streakDays)-day streak")
                }
            }
            ProportionBar(
                fraction: goal > 0 ? report.distractingSeconds / goal : 0,
                color: report.distractingSeconds > goal ? Theme.caution : Theme.accent, height: 3)
                .padding(.top, -Theme.Space.s)
            DayRibbon(segments: report.segments, day: model.now, now: model.now, height: 16, showsLabels: false)
            nowLine
            Divider()
            focusControls
            if [1, 2].contains(Calendar.current.component(.weekday, from: model.now)) {
                Button("This Week", systemImage: "calendar") {
                    openWindow(id: "weekly-review")
                    NSApp.activate()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.primary)
            }
            Divider()
            HStack {
                Button("Open Screentime++") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Spacer()
                Button {
                    openSettings()
                    NSApp.activate()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                .accessibilityLabel("Settings")
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("Quit Screentime++")
                .accessibilityLabel("Quit Screentime++")
            }
            .buttonStyle(.borderless)
            // Chrome stays neutral so colour only ever means data: the goal
            // bar, the ribbon and a running session.
            .foregroundStyle(.primary)
        }
        .padding(Theme.Space.m)
        .frame(width: 320)
        .onAppear { model.reloadToday() }
    }

    @ViewBuilder
    private var nowLine: some View {
        if !model.isAccessibilityTrusted {
            Label("Needs Accessibility access", systemImage: "exclamationmark.triangle")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.caution)
        } else if let context = model.live.context {
            let headline = FoldedText(context.headline)
            let coveringRule = model.live.evaluation.matches.first?.rule ?? model.configuration.rules.first {
                PolicyEngine.match(rule: $0, context: context, headline: headline, content: model.live.content) != nil
            }
            let grant = coveringRule.flatMap { model.runtime.grant(for: $0.id, at: model.now) }
            InFrontRow(subject: DraftSubject(context: context), coveredRule: coveringRule, grant: grant, now: model.now) { kind in
                model.presentRuleDraft(RuleDraft.rule(for: DraftSubject(context: context), kind: kind))
            } edit: { rule in
                model.editRule(id: rule.id)
            }
        }
    }

    @ViewBuilder
    private var focusControls: some View {
        if let focus = model.activeFocus {
            HStack {
                Image(systemName: "moon.fill").foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(focus.title).font(Theme.Font.body.weight(.medium))
                    Text("\(Format.countdown(focus.end.timeIntervalSince(model.now))) left\(focus.isLocked ? " \u{00B7} Locked" : "")")
                        .font(Theme.Font.caption).foregroundStyle(.secondary).monospacedDigit()
                    Button("Extend 15 min") { model.extendFocus(minutes: 15) }
                        .linkStyle()
                        .font(Theme.Font.caption)
                }
                Spacer()
                if !focus.isLocked {
                    Button("End") { model.endFocus() }
                        .accessibilityLabel("End Focus")
                }
            }
        } else {
            HStack(spacing: Theme.Space.s) {
                Text("Focus").font(Theme.Font.body.weight(.medium))
                Spacer()
                ForEach([25, 50, 90], id: \.self) { minutes in
                    Button("\(minutes)m") { startQuickFocus(minutes) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Start \(model.defaultFocusProfile.name) for \(minutes) minutes")
                        .accessibilityLabel("Start Focus for \(minutes) minutes")
                }
            }
        }
        pauseControls
    }

    /// The safety valve: deliberate (press and hold), short, and unavailable under a lock.
    @ViewBuilder
    private var pauseControls: some View {
        if let until = model.rulesPausedUntil {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack {
                    Image(systemName: "pause.circle.fill").foregroundStyle(Theme.caution)
                    Text("Rules paused until \(Format.clock(until))").font(Theme.Font.body)
                    Spacer()
                    Button("Resume") { model.resumeRules() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Text(model.today.bypassed == 0
                     ? "Time still counts. Anything a rule covers is logged."
                     : "Time still counts. \(model.today.bypassed) bypassed today, logged in Today.")
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
            }
        } else if model.canPauseRules {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HoldToConfirmButton(title: "Hold to pause all rules for 15 min", inset: false) { model.pauseRules(minutes: 15) }
                Text("Time still counts, and what you open is logged.")
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func startQuickFocus(_ minutes: Int) {
        model.startFocus(profile: model.defaultFocusProfile, minutes: minutes)
    }
}

/// The same compact activity controls are rendered with sample subjects in QA.
struct InFrontRow: View {
    let subject: DraftSubject
    var coveredRule: Rule? = nil
    var grant: AccessGrant? = nil
    var now: Date = Date()
    let draft: (DraftKind) -> Void
    let edit: (Rule) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("In Front").font(Theme.Font.caption).foregroundStyle(.secondary)
            HStack(spacing: Theme.Space.s) {
                SubjectIcon(bundleID: subject.bundleID, domain: subject.domain,
                            category: CategoryCatalog.category(bundleID: subject.bundleID, domain: subject.domain), size: 24)
                Text([subject.domain ?? subject.appName, subject.surface].compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.Font.body.weight(.medium))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            if let coveredRule {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text(coveredRule.name).font(Theme.Font.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Edit") { edit(coveredRule) }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.primary)
                        .accessibilityLabel("Edit \(coveredRule.name)")
                }
                if let grant {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        Text(Format.countdown(grant.until.timeIntervalSince(now)))
                            .font(Theme.Font.display(28)).monospacedDigit()
                        Label(grant.kind == .override ? "Override Left" : "Session Left",
                              systemImage: grant.kind == .override ? "exclamationmark.circle" : "timer")
                            .font(Theme.Font.caption)
                    }
                    .foregroundStyle(grant.kind == .override ? Theme.caution : Theme.accent)
                }
            } else {
                HStack(spacing: Theme.Space.s) {
                    Button("Pause") { draft(.pause) }
                    Button("Limit") { draft(.limit) }
                    Button("Block") { draft(.block) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
