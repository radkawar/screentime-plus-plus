import ScreentimeCore
import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var showsAllItems = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsLibrary = false
    @State private var editing: Rule?

    var body: some View {
        let summary = model.today
        let report = summary.report
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                if !model.isAccessibilityTrusted {
                    PermissionCallout()
                }
                if report.totalSeconds == 0 && report.segments.isEmpty {
                    TodayFirstDayState(
                        appName: model.live.context?.appName,
                        isWatching: model.live.status == .active,
                        browse: { showsLibrary = true })
                } else {
                    headline(report: report, streak: summary.streakDays)
                    DayRibbon(segments: report.segments, day: model.now, now: model.now, height: 44)
                    stats(summary)
                    items(report)
                }
                if !summary.interventions.isEmpty {
                    interventions(summary.interventions)
                }
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.l)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Today")
        .onAppear { model.reloadToday() }
        .sheet(isPresented: $showsLibrary) {
            TemplatePicker { template in
                showsLibrary = false
                editing = template.make()
            }
        }
        .sheet(item: $editing) { RuleEditor(rule: $0, isNew: true) }
    }

    // MARK: Headline

    private func headline(report: UsageReport, streak: Int) -> some View {
        let goal = TimeInterval(model.configuration.settings.dailyGoalMinutes * 60)
        let distracting = report.distractingSeconds
        let over = distracting - goal
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(Theme.Font.label)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Spacer()
                if streak > 0 {
                    Label("\(streak)-day streak", systemImage: "flame")
                        .font(Theme.Font.label)
                        .foregroundStyle(Theme.accent)
                        .help("Days with distracting time inside your goal and no overrides")
                }
            }
            Text(Format.duration(distracting, showSeconds: true))
                .font(Theme.Font.display(64))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .accessibilityLabel("\(Format.spokenDuration(distracting)) of distracting time")
            Text(
                "distracting, of \(Format.duration(report.totalSeconds)) on screen. "
                    + (over > 0
                        ? "\(Format.duration(over)) over your \(Format.duration(goal)) goal."
                        : "\(Format.duration(-over)) left of your \(Format.duration(goal)) goal.")
            )
            .font(Theme.Font.body)
            .foregroundStyle(.secondary)
            ProportionBar(fraction: goal > 0 ? distracting / goal : 0, color: over > 0 ? Theme.caution : Theme.accent, height: 5)
                .frame(maxWidth: 360)
                .padding(.top, Theme.Space.xs)
        }
    }

    // MARK: Stats

    private func stats(_ summary: TodaySummary) -> some View {
        let report = summary.report
        let shown = summary.interventions.count
        return FlowLayout(spacing: Theme.Space.xl, lineSpacing: Theme.Space.m) {
            Stat(value: "\(report.sessions.count)", label: "pickups")
            Stat(value: Format.duration(report.longestSession), label: "longest stretch")
            Stat(
                value: shown == 0 ? "None" : "\(summary.turnedBack) of \(shown)",
                label: shown == 0 ? "interventions" : "times you turned back")
        }
    }

    // MARK: Items

    @ViewBuilder
    private func items(_ report: UsageReport) -> some View {
        let items = report.items
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionTitle(title: "Apps & Sites", trailing: items.isEmpty ? nil : "\(items.count)")
            if items.isEmpty {
                Text("Nothing recorded yet today. Time shows up here within a minute of use.")
                    .font(Theme.Font.body)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, Theme.Space.s)
            } else {
                let visible = showsAllItems ? items : Array(items.prefix(8))
                let maxSeconds = items.first?.seconds ?? 1
                VStack(spacing: 0) {
                    ForEach(visible) { item in
                        UsageRow(item: item, maxSeconds: maxSeconds)
                        if item.id != visible.last?.id { Divider().padding(.leading, 44) }
                    }
                }
                if items.count > 8 {
                    Button(showsAllItems ? "Show Fewer" : "Show All \(items.count)") {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { showsAllItems.toggle() }
                    }
                    .buttonStyle(.borderless)
                    .font(Theme.Font.body)
                }
            }
        }
    }

    // MARK: Interventions

    private func interventions(_ records: [InterventionRecord]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionTitle(title: "Interventions", trailing: "\(records.count)")
            VStack(spacing: 0) {
                ForEach(records.prefix(12)) { record in
                    InterventionRow(record: record)
                    if record.id != records.prefix(12).last?.id { Divider() }
                }
            }
        }
    }
}

/// The empty day is a useful starting point, not a zero-valued report.
struct TodayFirstDayState: View {
    let appName: String?
    var isWatching = true
    let browse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text("Your day starts here.")
                .font(Theme.Font.display(40))
                .accessibilityAddTraits(.isHeader)
            Text("As you use your Mac, your apps, sites and time on screen appear here. Your day ribbon will show when you used them.")
                .font(Theme.Font.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label(
                isWatching ? "Watching: \(appName ?? "your next app")" : "Ready when you return to an app",
                systemImage: isWatching ? "eye" : "clock")
                .font(Theme.Font.body.weight(.medium))
                .foregroundStyle(Theme.accent)
                .padding(Theme.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Choose what counts as distracting.")
                    .font(Theme.Font.heading)
                Text("Add a rule from the Library to track, pause or block an app, site or page. You can change it later in Rules.")
                    .font(Theme.Font.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Browse the Library…", action: browse)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, Theme.Space.xs)
            }
        }
        .padding(.vertical, Theme.Space.l)
    }
}

private struct Stat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 20, weight: .medium, design: .serif)).monospacedDigit()
            Text(label).font(Theme.Font.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct InterventionRow: View {
    let record: InterventionRecord

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Text(Format.clock(record.at))
                .font(Theme.Font.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(record.subject)").font(Theme.Font.body.weight(.medium))
                HStack(spacing: 4) {
                    Text(record.ruleName)
                    if let intention = record.intention {
                        Text("\u{00B7} \u{201C}\(intention)\u{201D}").italic()
                    }
                }
                .font(Theme.Font.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            outcome
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }

    private var outcome: some View {
        let (text, symbol, color): (String, String, Color) =
            switch record.outcome {
            case .shown: ("Shown", "eye", .secondary)
            case .turnedBack: ("Turned back", "arrow.uturn.backward", Theme.accent)
            case .continued: ("Continued", "arrow.right", .secondary)
            case .overridden: ("Overrode", "exclamationmark.circle", Theme.caution)
            case .closed: ("Closed", "xmark.circle", Theme.accent)
            }
        return Label(text, systemImage: symbol)
            .font(Theme.Font.caption)
            .foregroundStyle(color)
    }
}

struct PermissionCallout: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Image(systemName: "lock.shield")
                .font(.system(size: 20))
                .foregroundStyle(Theme.caution)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Accessibility access is off").font(Theme.Font.heading)
                Text(
                    "Screentime++ can\u{2019}t see which site or page is in front, so time isn\u{2019}t attributed and rules can\u{2019}t act. Turn on Screentime++ in Privacy & Security \u{203A} Accessibility."
                )
                .font(Theme.Font.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Open Settings\u{2026}") { model.requestAccessibility() }
                .buttonStyle(.borderedProminent)
        }
        .padding(Theme.Space.m)
        .background(Theme.cautionSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
    }
}
