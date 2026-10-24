import Foundation

/// Two adjacent seven-calendar-day windows, including the current partial day.
public struct WeeklyReview: Sendable {
    public struct Period: Sendable {
        public let report: UsageReport
        public let days: [DayTotal]
        public let interventions: [InterventionRecord]
        public let daysInsideGoal: Int
        public let recordedDays: Int
        public let longestStreak: Int
        public let mostPausedRule: String?
        public let pauseCount: Int

        public var turnedBackRate: Double? {
            guard !interventions.isEmpty else { return nil }
            return Double(interventions.filter { $0.outcome == .turnedBack || $0.outcome == .closed }.count)
                / Double(interventions.count)
        }

        public var intentions: [InterventionRecord] {
            interventions.filter { !($0.intention?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }
        }

        fileprivate init(report: UsageReport, interventions: [InterventionRecord], goal: TimeInterval, calendar: Calendar) {
            self.report = report
            days = report.daily(calendar: calendar)
            self.interventions = interventions.filter { $0.at >= report.interval.start && $0.at < report.interval.end }
                .sorted { $0.at < $1.at }
            recordedDays = days.filter { $0.seconds > 0 }.count
            daysInsideGoal = days.filter { $0.seconds > 0 && $0.distractingSeconds <= goal }.count
            let overridden = Set(self.interventions.filter { $0.outcome == .overridden }.map { calendar.startOfDay(for: $0.at) })
            var run = 0
            var longest = 0
            for day in days {
                // An unrecorded day is unknown, not evidence of a successful day.
                if day.seconds > 0 && day.distractingSeconds <= goal && !overridden.contains(day.day) {
                    run += 1
                    longest = max(longest, run)
                } else {
                    run = 0
                }
            }
            longestStreak = longest
            let pauses = Dictionary(grouping: self.interventions.filter { $0.kind == .pause }, by: \.ruleID)
            let winner = pauses.values.sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return ($0.last?.ruleName ?? "") < ($1.last?.ruleName ?? "")
            }.first
            mostPausedRule = winner?.last?.ruleName
            pauseCount = winner?.count ?? 0
        }
    }

    public struct Item: Sendable, Identifiable {
        public let usage: UsageTotal
        public let previousSeconds: TimeInterval
        public var id: String { usage.id }
        public var change: TimeInterval { usage.seconds - previousSeconds }
    }

    public let current: Period
    public let previous: Period
    public let goalSeconds: TimeInterval
    public let topItems: [Item]

    public init(segments: [Segment], interventions: [InterventionRecord], goalMinutes: Int, now: Date, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -6, to: today)!
        let previousStart = calendar.date(byAdding: .day, value: -7, to: start)!
        goalSeconds = TimeInterval(max(0, goalMinutes)) * 60
        current = Period(
            report: UsageReport(segments: segments, interval: DateInterval(start: start, end: max(now, today.addingTimeInterval(0.001)))),
            interventions: interventions, goal: goalSeconds, calendar: calendar)
        previous = Period(
            report: UsageReport(segments: segments, interval: DateInterval(start: previousStart, end: start)),
            interventions: interventions, goal: goalSeconds, calendar: calendar)
        let old = Dictionary(uniqueKeysWithValues: previous.report.items.map { ($0.id, $0.seconds) })
        topItems = current.report.items.prefix(5).map { Item(usage: $0, previousSeconds: old[$0.id] ?? 0) }
    }
}
