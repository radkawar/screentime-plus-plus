import XCTest
@testable import ScreentimeCore

final class WeeklyReviewTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }
    private let rule = UUID()

    private func date(_ day: Int, hour: Int = 12, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func segment(_ day: Int, minutes: Int, domain: String = "example.com") -> Segment {
        let start = date(day)
        return Segment(start: start, end: start.addingTimeInterval(Double(minutes) * 60),
                       bundleID: "com.apple.Safari", appName: "Safari", domain: domain,
                       surface: nil, category: .reading, ruleID: rule)
    }

    private func event(_ day: Int, outcome: InterventionOutcome, intention: String? = nil) -> InterventionRecord {
        InterventionRecord(id: Int64(day), at: date(day), ruleID: rule, ruleName: "Read Mindfully",
                           kind: .pause, subject: "example.com", outcome: outcome, intention: intention)
    }

    func testComparesAdjacentWindowsAndTopItemChanges() {
        let segments = [segment(11, minutes: 5), segment(17, minutes: 10), segment(18, minutes: 20), segment(24, minutes: 30)]
        let review = WeeklyReview(segments: segments, interventions: [], goalMinutes: 25,
                                  now: date(24, hour: 18), calendar: calendar)
        XCTAssertEqual(review.current.days.count, 7)
        XCTAssertEqual(review.previous.days.count, 7)
        XCTAssertEqual(review.current.report.interval.start, date(18, hour: 0))
        XCTAssertEqual(review.previous.report.interval.start, date(11, hour: 0))
        XCTAssertEqual(review.current.report.totalSeconds, 50 * 60)
        XCTAssertEqual(review.previous.report.totalSeconds, 15 * 60)
        XCTAssertEqual(review.current.recordedDays, 2)
        XCTAssertEqual(review.current.daysInsideGoal, 1)
        XCTAssertEqual(review.topItems.first?.change, 35 * 60)
        XCTAssertNil(review.current.turnedBackRate)
    }

    func testRatesIntentionsPauseCountsAndOverrideBrokenStreak() {
        let segments = (18...24).map { segment($0, minutes: 20) }
        let events = [event(17, outcome: .closed), event(18, outcome: .turnedBack), event(19, outcome: .closed),
                      event(20, outcome: .overridden), event(21, outcome: .continued, intention: "Read a saved article."),
                      event(24, outcome: .shown, intention: " \n ")]
        let review = WeeklyReview(segments: segments, interventions: events, goalMinutes: 20,
                                  now: date(24, hour: 18), calendar: calendar)
        XCTAssertEqual(review.current.turnedBackRate ?? -1, 0.4, accuracy: 0.0001)
        XCTAssertEqual(review.current.longestStreak, 4)
        XCTAssertEqual(review.current.daysInsideGoal, 7)
        XCTAssertEqual(review.current.mostPausedRule, "Read Mindfully")
        XCTAssertEqual(review.current.pauseCount, 5)
        XCTAssertEqual(review.current.intentions.map(\.intention), ["Read a saved article."])
        XCTAssertEqual(review.previous.pauseCount, 1)
    }

    func testUsingSomethingWhileRulesArePausedBreaksTheStreak() {
        let segments = (18...24).map { segment($0, minutes: 20) }
        let review = WeeklyReview(segments: segments, interventions: [event(21, outcome: .bypassed)], goalMinutes: 20,
                                  now: date(24, hour: 18), calendar: calendar)
        XCTAssertEqual(review.current.longestStreak, 3)
        XCTAssertEqual(review.current.turnedBackRate, 0)
    }

    func testMissingDaysBreakStreakAndEmptyHistoryDoesNotInventSuccess() {
        let review = WeeklyReview(segments: [segment(18, minutes: 10), segment(20, minutes: 10)],
                                  interventions: [], goalMinutes: 90, now: date(24), calendar: calendar)
        XCTAssertEqual(review.current.longestStreak, 1)
        XCTAssertEqual(review.previous.longestStreak, 0)
        XCTAssertEqual(review.previous.daysInsideGoal, 0)
        XCTAssertNil(review.previous.mostPausedRule)
    }

    func testCalendarDaysSurviveDaylightSavingAndClipCrossingSegments() {
        let boundary = date(1, hour: 0, month: 11)
        let crossing = Segment(start: boundary.addingTimeInterval(-1800), end: boundary.addingTimeInterval(1800),
                               bundleID: "com.apple.Safari", appName: "Safari", domain: nil,
                               surface: nil, category: .reading, ruleID: rule)
        let review = WeeklyReview(segments: [crossing], interventions: [], goalMinutes: 60,
                                  now: date(7, hour: 12, month: 11), calendar: calendar)
        XCTAssertEqual(review.current.days.count, 7)
        XCTAssertEqual(review.current.report.interval.start, boundary)
        XCTAssertEqual(review.current.report.totalSeconds, 1800)
        XCTAssertEqual(review.previous.report.totalSeconds, 1800)
        XCTAssertEqual(review.current.days.first?.day, boundary)
    }

    func testTopItemsAreLimitedToFiveAndNewItemsHaveZeroPreviousUsage() {
        let segments = (1...6).map { segment(23, minutes: $0, domain: "site\($0).example") }
        let review = WeeklyReview(segments: segments, interventions: [], goalMinutes: 60,
                                  now: date(24), calendar: calendar)
        XCTAssertEqual(review.topItems.count, 5)
        XCTAssertEqual(review.topItems.first?.usage.title, "site6.example")
        XCTAssertTrue(review.topItems.allSatisfy { $0.previousSeconds == 0 })
    }

    func testNotificationSettingsDecodeOldConfigurationsAndRoundTrip() throws {
        let original = AppSettings()
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(original))
        XCTAssertNil(decoded.weeklyReviewNotifications)
        XCTAssertNil(decoded.sessionEndingNotifications)
        XCTAssertNil(decoded.goalNotifications)
        var enabled = decoded
        enabled.weeklyReviewNotifications = true
        enabled.sessionEndingNotifications = true
        enabled.goalNotifications = true
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(enabled)), enabled)
    }
}
