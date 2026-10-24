import ScreentimeCore
import SwiftUI

struct DayDetailView: View {
    @Environment(AppModel.self) private var model
    let day: Date
    var sample: TodaySummary?
    var close: (() -> Void)?
    @State private var loaded: TodaySummary?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                if let close {
                    Button("Back to History", systemImage: "chevron.left", action: close)
                        .buttonStyle(.borderless)
                }
                if let summary = sample ?? loaded {
                    DayHeadline(report: summary.report, day: day, goalMinutes: model.configuration.settings.dailyGoalMinutes)
                    DayRibbon(segments: summary.report.segments, day: day, now: model.now, height: 44)
                    DayStats(summary: summary)
                    UsageItems(report: summary.report)
                    if summary.interventions.isEmpty {
                        SectionTitle(title: "Interventions", trailing: "None")
                    } else {
                        DayInterventions(records: summary.interventions)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.l)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(day.formatted(.dateTime.month(.wide).day()))
        .task(id: day) {
            guard sample == nil else { return }
            loaded = await model.history(on: day)
        }
    }
}

#if DEBUG
enum HistoryDetailSamples {
    static let day = Calendar.current.startOfDay(for: Date())
    static let rule = Rule(name: "YouTube Shorts", targets: [.urlPattern("youtube.com/shorts/*")])
    static let site = DraftSubject(bundleID: "com.apple.Safari", appName: "Safari", domain: "youtube.com")
    static let app = DraftSubject(bundleID: "com.apple.dt.Xcode", appName: "Xcode")

    static var week: UsageReport {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -6, to: day)!
        let end = calendar.date(byAdding: .day, value: 1, to: day)!
        var segments: [Segment] = []
        for offset in 0..<7 {
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            let morning = date.addingTimeInterval(9 * 3600)
            let noon = date.addingTimeInterval(12 * 3600)
            let afternoon = date.addingTimeInterval(15 * 3600)
            segments.append(Segment(id: Int64(offset * 3), start: morning, end: morning.addingTimeInterval(Double(40 + offset * 8) * 60),
                                    bundleID: app.bundleID, appName: app.appName, domain: nil, surface: nil, category: .productivity, ruleID: nil))
            segments.append(Segment(id: Int64(offset * 3 + 1), start: noon, end: noon.addingTimeInterval(Double(12 + offset * 3) * 60),
                                    bundleID: site.bundleID, appName: site.appName, domain: site.domain, surface: "Shorts", category: .entertainment, ruleID: rule.id))
            segments.append(Segment(id: Int64(offset * 3 + 2), start: afternoon, end: afternoon.addingTimeInterval(22 * 60),
                                    bundleID: site.bundleID, appName: site.appName, domain: site.domain, surface: "Watch", category: .entertainment, ruleID: nil))
        }
        return UsageReport(segments: segments, interval: DateInterval(start: start, end: end))
    }

    static var summary: TodaySummary {
        TodaySummary(report: week.on(day: day), interventions: [
            InterventionRecord(at: day.addingTimeInterval(12 * 3600), ruleID: rule.id, ruleName: rule.name,
                               kind: .pause, subject: "youtube.com", outcome: .turnedBack)
        ], streakDays: 0)
    }
}
#endif
