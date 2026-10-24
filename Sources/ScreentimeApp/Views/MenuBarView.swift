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
                    Text(Format.duration(report.distractingSeconds))
                        .font(Theme.Font.display(30))
                        .monospacedDigit()
                    Text("distracting of \(Format.duration(goal)) \u{00B7} \(Format.duration(report.totalSeconds)) total")
                        .font(Theme.Font.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                if model.today.streakDays > 0 {
                    Label("\(model.today.streakDays)", systemImage: "flame")
                        .font(Theme.Font.label)
                        .foregroundStyle(Theme.ember)
                        .help("\(model.today.streakDays)-day streak")
                }
            }
            DayRibbon(segments: report.segments, day: model.now, now: model.now, height: 16, showsLabels: false)
            nowLine
            Divider()
            focusControls
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
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("Quit Screentime++")
            }
            .buttonStyle(.borderless)
        }
        .padding(Theme.Space.m)
        .frame(width: 320)
        .tint(Theme.ember)
        .onAppear { model.reloadToday() }
    }

    @ViewBuilder
    private var nowLine: some View {
        if !model.isAccessibilityTrusted {
            Label("Needs Accessibility access", systemImage: "exclamationmark.triangle")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.ember)
        } else if let context = model.live.context {
            let grant = model.live.evaluation.matches.lazy.compactMap { match in
                model.runtime.grant(for: match.rule.id, at: model.now).map { (match.rule, $0) }
            }.first
            HStack(spacing: Theme.Space.s) {
                SubjectIcon(bundleID: context.bundleID, domain: context.domain, category: context.category, size: 18)
                Text(context.domain ?? context.appName).font(Theme.Font.body).lineLimit(1)
                Spacer()
                if let (rule, grant) = grant {
                    Text("\(rule.name) \u{00B7} \(Format.countdown(grant.until.timeIntervalSince(model.now))) left")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.ember)
                        .monospacedDigit()
                } else if let match = model.live.evaluation.matches.first {
                    Text(match.rule.name).font(Theme.Font.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var focusControls: some View {
        if let focus = model.activeFocus {
            HStack {
                Image(systemName: "moon.fill").foregroundStyle(Theme.ember)
                VStack(alignment: .leading, spacing: 1) {
                    Text(focus.title).font(Theme.Font.body.weight(.medium))
                    Text("\(Format.countdown(focus.end.timeIntervalSince(model.now))) left\(focus.isLocked ? " \u{00B7} Locked" : "")")
                        .font(Theme.Font.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                if !focus.isLocked {
                    Button("End") { model.endFocus() }
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
                        .help("Block your focus rules for \(minutes) minutes")
                }
            }
        }
    }

    private func startQuickFocus(_ minutes: Int) {
        let ids = model.configuration.rules.filter { rule in
            if case .duringFocus = rule.schedule { return true }
            if case .track = rule.response { return false }
            return rule.isEnabled
        }.map(\.id)
        model.startFocus(minutes: minutes, ruleIDs: ids, locked: false)
    }
}
