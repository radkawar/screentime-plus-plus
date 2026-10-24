import ScreentimeCore
import SwiftUI

/// Value-driven so the gallery never needs to read personal history.
struct WeeklyReviewView: View {
    let review: WeeklyReview
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                header
                ribbon
                comparisons
                topItems
                reflection
                intentions
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas)
        .navigationTitle("This Week")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("YOUR WEEK, IN PERSPECTIVE")
                .font(Theme.Font.label).tracking(0.6).foregroundStyle(.secondary)
            Text("This Week").font(Theme.Font.display(40))
            Text("\(review.current.report.interval.start.formatted(date: .abbreviated, time: .omitted)) – \(review.current.report.interval.end.formatted(date: .abbreviated, time: .omitted))")
                .font(Theme.Font.body).foregroundStyle(.secondary)
            Text("\(review.current.daysInsideGoal) of \(review.current.recordedDays) recorded days inside your goal")
                .font(Theme.Font.heading).padding(.top, Theme.Space.s)
            Text("\(review.previous.daysInsideGoal) of \(review.previous.recordedDays) the week before.")
                .font(Theme.Font.caption).foregroundStyle(.secondary)
            Text("Your daily goal is \(Format.duration(review.goalSeconds)). Today is still in progress; comparisons use the seven days before this window.")
                .font(Theme.Font.body).foregroundStyle(.secondary)
        }
    }

    private var ribbon: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .bottom, spacing: Theme.Space.s) {
                ForEach(review.current.days) { day in
                    let recorded = day.seconds > 0
                    let inside = day.distractingSeconds <= review.goalSeconds
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text(day.day, format: .dateTime.weekday(.abbreviated))
                            .font(Theme.Font.label).foregroundStyle(.secondary)
                        DayRibbon(segments: review.current.report.segments, day: day.day, height: 48, showsLabels: false)
                        HStack(spacing: Theme.Space.xs) {
                            Image(systemName: !recorded ? "minus" : inside ? "checkmark" : "arrow.up")
                                .foregroundStyle(!recorded ? Color.secondary : inside ? Theme.accent : Theme.caution)
                            Text(recorded ? Format.duration(day.distractingSeconds) : "—")
                                .monospacedDigit()
                        }
                        .font(Theme.Font.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.day.formatted(date: .complete, time: .omitted)), \(recorded ? Format.spokenDuration(day.distractingSeconds) + (inside ? ", inside goal" : ", over goal") : "no recorded activity")")
                }
            }
            Text("Each strip is one day, midnight to midnight. Labels show distracting time.")
                .font(Theme.Font.caption).foregroundStyle(.secondary)
        }
    }

    private var comparisons: some View {
        VStack(spacing: Theme.Space.m) {
            metric("Distracting Time", current: Format.duration(review.current.report.distractingSeconds),
                   previous: Format.duration(review.previous.report.distractingSeconds))
            Divider()
            metric("Total Screen Time", current: Format.duration(review.current.report.totalSeconds),
                   previous: Format.duration(review.previous.report.totalSeconds))
            Divider()
            metric("Turned-Back Rate", current: rate(review.current.turnedBackRate), previous: rate(review.previous.turnedBackRate))
            Text("Turned back or closed, divided by all interventions. No interventions means no rate.")
                .font(Theme.Font.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metric(_ title: String, current: String, previous: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Theme.Font.body)
            Spacer()
            VStack(alignment: .trailing, spacing: Theme.Space.xs) {
                Text(current).font(Theme.Font.display(28)).monospacedDigit()
                Text("\(previous) the week before").font(Theme.Font.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var topItems: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionTitle(title: "Your Top Apps & Sites")
            if review.topItems.isEmpty {
                Text("Your recorded apps and sites will appear here.").font(Theme.Font.body).foregroundStyle(.secondary)
            }
            ForEach(review.topItems) { item in
                HStack(spacing: Theme.Space.s) {
                    SubjectIcon(bundleID: item.usage.bundleID, domain: item.usage.domain, category: item.usage.category, size: 28)
                    Text(item.usage.title).font(Theme.Font.body).lineLimit(1)
                    Spacer()
                    VStack(alignment: .trailing, spacing: Theme.Space.xs) {
                        Text(Format.duration(item.usage.seconds)).font(Theme.Font.body).monospacedDigit()
                        Label(
                            item.previousSeconds == 0
                                ? "New this week"
                                : item.change == 0
                                    ? "Same as the week before"
                                    : "\(Format.duration(abs(item.change))) \(item.change > 0 ? "more" : "less")",
                              systemImage: item.change > 0 ? "arrow.up" : item.change < 0 ? "arrow.down" : "minus")
                            .font(Theme.Font.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var reflection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionTitle(title: "A Little Perspective")
            Label("\(review.current.longestStreak)-day longest streak · \(review.previous.longestStreak) the week before", systemImage: "flame")
                .foregroundStyle(Theme.accent)
            Text("A streak is consecutive recorded days inside your goal, without overrides.")
                .font(Theme.Font.caption).foregroundStyle(.secondary)
            if let rule = review.current.mostPausedRule {
                Text("Most-paused rule: \(rule) · \(review.current.pauseCount) pauses")
            } else {
                Text("No pause interventions this week.")
            }
            if let previous = review.previous.mostPausedRule {
                Text("The week before: \(previous) · \(review.previous.pauseCount) pauses")
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
            }
        }
        .font(Theme.Font.body)
    }

    private var intentions: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionTitle(title: "In Your Words")
            if review.current.intentions.isEmpty {
                Text("No intentions recorded this week.").font(Theme.Font.body).foregroundStyle(.secondary)
            }
            ForEach(review.current.intentions) { event in
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(event.intention ?? "").font(Theme.Font.body)
                    Text("\(event.subject) · \(event.at.formatted(.dateTime.weekday(.wide).hour().minute()))")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                }
                .textSelection(.enabled)
            }
        }
    }

    private func rate(_ value: Double?) -> String {
        value.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—"
    }
}

struct WeeklyReviewSheet: View {
    @Environment(AppModel.self) private var model
    @State private var review: WeeklyReview?

    var body: some View {
        NavigationStack {
            Group {
                if let review { WeeklyReviewView(review: review) }
                else { ProgressView("Gathering Your Week…") }
            }
            .frame(minWidth: 600, minHeight: 560)
        }
        .task {
            let (report, interventions) = await model.history(days: 14)
            guard !Task.isCancelled else { return }
            review = WeeklyReview(segments: report.segments, interventions: interventions,
                                  goalMinutes: model.configuration.settings.dailyGoalMinutes, now: Date())
        }
    }
}

#if DEBUG
extension WeeklyReview {
    static var gallery: WeeklyReview {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let rule = UUID()
        var segments: [Segment] = []
        var events: [InterventionRecord] = []
        for offset in -13...0 {
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            let start = calendar.date(byAdding: .hour, value: 9, to: day)!
            segments.append(Segment(start: start, end: start.addingTimeInterval(Double(30 + abs(offset) * 5) * 60),
                                    bundleID: "com.apple.Safari", appName: "Safari", domain: "youtube.com", surface: nil,
                                    category: .entertainment, ruleID: rule))
            let work = start.addingTimeInterval(7200)
            segments.append(Segment(start: work, end: work.addingTimeInterval(7200), bundleID: "com.apple.dt.Xcode",
                                    appName: "Xcode", domain: nil, surface: nil, category: .productivity, ruleID: nil))
            events.append(InterventionRecord(id: Int64(offset + 14), at: start, ruleID: rule, ruleName: "Mindful Video",
                                             kind: .pause, subject: "youtube.com", outcome: offset % 3 == 0 ? .continued : .turnedBack,
                                             intention: offset == -2 ? "Watch the talk I saved for lunch." : nil))
        }
        return WeeklyReview(segments: segments, interventions: events, goalMinutes: 75, now: now)
    }
}
#endif
