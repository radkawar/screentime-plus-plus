import XCTest

@testable import ScreentimeCore

final class UsageTrackingTests: XCTestCase {
    private var directory: URL!
    private var store: UsageStore!
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = try UsageStore(path: directory.appendingPathComponent("usage.sqlite").path)
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: directory)
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(
            from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second))!
    }

    private let youtube = ForegroundContext(
        bundleID: "com.apple.Safari", appName: "Safari", pid: 1, isBrowser: true,
        url: URL(string: "https://www.youtube.com/shorts/1"))
    private let xcode = ForegroundContext(bundleID: "com.apple.Xcode", appName: "Xcode", pid: 2, isBrowser: false)

    private func match(_ rule: Rule) -> RuleMatch {
        RuleMatch(rule: rule, target: rule.targets[0], evidence: .website("youtube.com"))
    }

    func testContinuousSamplesBecomeOneSegmentPerSubject() throws {
        let tracker = UsageTracker(store: store, calendar: calendar, now: date(21, 10))
        for second in 0...12 { tracker.record(context: youtube, matches: [], isShielded: false, at: date(21, 10, 0, second)) }
        for second in 13...20 { tracker.record(context: xcode, matches: [], isShielded: false, at: date(21, 10, 0, second)) }
        tracker.flush(at: date(21, 10, 0, 20))

        let report = UsageReport(
            segments: try store.segments(in: DateInterval(start: date(21, 0), end: date(22, 0))),
            interval: DateInterval(start: date(21, 0), end: date(22, 0)))
        XCTAssertEqual(report.totalSeconds, 20, accuracy: 0.001)
        let items = report.items
        XCTAssertEqual(items.map(\.title), ["youtube.com", "Xcode"])
        XCTAssertEqual(items[0].surfaces.first?.name, "Shorts")
        XCTAssertEqual(report.sessions.count, 1)
    }

    func testIdleGapAndShieldTimeAreNotCounted() throws {
        let rule = Rule(name: "YT", targets: [.website(domain: "youtube.com")], response: .track)
        let tracker = UsageTracker(store: store, calendar: calendar, now: date(21, 10))
        for second in 0...5 {
            tracker.record(context: youtube, matches: [match(rule)], isShielded: false, at: date(21, 10, 0, second))
        }
        // Shielded for 30 seconds.
        for second in 6...35 {
            tracker.record(context: youtube, matches: [match(rule)], isShielded: true, at: date(21, 10, 0, second))
        }
        // Idle, then back after ten minutes.
        tracker.record(context: nil, matches: [], isShielded: false, at: date(21, 10, 1))
        for second in 0...4 {
            tracker.record(context: youtube, matches: [match(rule)], isShielded: false, at: date(21, 10, 11, second))
        }
        tracker.flush(at: date(21, 10, 11, 4))

        XCTAssertEqual(tracker.ruleUsage[rule.id]?.seconds ?? 0, 9, accuracy: 0.001)
        // Entered twice, more than a minute apart.
        XCTAssertEqual(tracker.ruleUsage[rule.id]?.opens, 2)
        let report = UsageReport(
            segments: try store.segments(in: DateInterval(start: date(21, 0), end: date(22, 0))),
            interval: DateInterval(start: date(21, 0), end: date(22, 0)))
        XCTAssertEqual(report.totalSeconds, 9, accuracy: 0.001)
        XCTAssertEqual(report.distractingSeconds, 9, accuracy: 0.001)
        XCTAssertEqual(report.sessions.count, 2)
    }

    func testPauseRulesCountOpensOnlyWhenContinued() {
        let rule = Rule(name: "YT", targets: [.website(domain: "youtube.com")], response: .pause(PauseSettings()))
        let tracker = UsageTracker(store: store, calendar: calendar, now: date(21, 10))
        tracker.record(context: youtube, matches: [match(rule)], isShielded: false, at: date(21, 10))
        XCTAssertEqual(tracker.ruleUsage[rule.id]?.opens ?? 0, 0)
        tracker.registerOpen(ruleID: rule.id, at: date(21, 10, 0, 1))
        XCTAssertEqual(tracker.ruleUsage[rule.id]?.opens, 1)
    }

    func testMidnightSplitsSegmentsAndResetsCounters() throws {
        let rule = Rule(name: "YT", targets: [.website(domain: "youtube.com")], response: .track)
        let tracker = UsageTracker(store: store, calendar: calendar, now: date(21, 23, 59, 50))
        for second in 50...59 {
            tracker.record(context: youtube, matches: [match(rule)], isShielded: false, at: date(21, 23, 59, second))
        }
        for second in 0...10 {
            tracker.record(context: youtube, matches: [match(rule)], isShielded: false, at: date(22, 0, 0, second))
        }
        tracker.flush(at: date(22, 0, 0, 10))

        XCTAssertEqual(tracker.day, "2026-10-22")
        XCTAssertEqual(tracker.ruleUsage[rule.id]?.seconds ?? 0, 11, accuracy: 0.001)
        XCTAssertEqual(try store.ruleUsage(day: "2026-10-21")[rule.id]?.seconds ?? 0, 9, accuracy: 0.001)

        let both = DateInterval(start: date(21, 0), end: date(23, 0))
        let days = UsageReport(segments: try store.segments(in: both), interval: both).daily(calendar: calendar)
        XCTAssertEqual(days.map(\.seconds), [10, 10])
    }

    func testHourlyBucketsSplitAtHourBoundaries() {
        let segment = Segment(
            start: date(21, 9, 50), end: date(21, 10, 20), bundleID: "a", appName: "A", domain: nil, surface: nil,
            category: .productivity, ruleID: nil)
        let report = UsageReport(segments: [segment], interval: DateInterval(start: date(21, 0), end: date(22, 0)))
        let hourly = report.hourly(calendar: calendar)
        XCTAssertEqual(hourly[9][.productivity] ?? 0, 600, accuracy: 0.001)
        XCTAssertEqual(hourly[10][.productivity] ?? 0, 1_200, accuracy: 0.001)
    }

    func testInterventionOutcomeUpdates() throws {
        let id = try store.insert(
            InterventionRecord(
                at: date(21, 10), ruleID: UUID(), ruleName: "YT", kind: .pause, subject: "youtube.com", outcome: .shown))
        try store.update(interventionID: id, outcome: .continued, intention: "Watch the WWDC talk")
        let records = try store.interventions(in: DateInterval(start: date(21, 0), end: date(22, 0)))
        XCTAssertEqual(records.first?.outcome, .continued)
        XCTAssertEqual(records.first?.intention, "Watch the WWDC talk")
    }

    func testResumingEarlyEndsOnlyTheRunningPauseAndQueriesOverlap() throws {
        try store.insert(RulePause(start: date(21, 9), end: date(21, 9, 15)))
        try store.insert(RulePause(start: date(21, 10), end: date(21, 10, 15)))
        try store.endRulePauses(at: date(21, 10, 4))
        let pauses = try store.rulePauses(in: DateInterval(start: date(21, 0), end: date(22, 0)))
        XCTAssertEqual(pauses.map(\.end), [date(21, 9, 15), date(21, 10, 4)])
        // A pause crossing the start of a query interval still belongs to it.
        XCTAssertEqual(try store.rulePauses(in: DateInterval(start: date(21, 9, 10), end: date(21, 9, 30))).count, 1)
        try store.deleteAll()
        XCTAssertTrue(try store.rulePauses(in: DateInterval(start: date(21, 0), end: date(22, 0))).isEmpty)
    }

    func testPausedUseClipsToThePauseAndIgnoresUncoveredTime() {
        let social = UUID()
        let chat = UUID()
        func segment(_ from: Int, _ to: Int, _ domain: String?, _ rule: UUID?) -> Segment {
            Segment(start: date(21, 10, from), end: date(21, 10, to), bundleID: "app", appName: "Discord",
                    domain: domain, surface: nil, category: .social, ruleID: rule)
        }
        let pause = RulePause(start: date(21, 10, 5), end: date(21, 10, 20))
        let used = pause.coveredUse(in: [
            segment(0, 8, "x.com", social),      // 3 minutes inside the pause
            segment(8, 10, nil, nil),            // not covered by a rule
            segment(10, 14, "reddit.com", social),
            segment(14, 16, nil, chat),
            segment(25, 30, "x.com", social),    // after the pause
        ])
        XCTAssertEqual(used.map(\.ruleID), [social, chat])
        XCTAssertEqual(used.map(\.seconds), [7 * 60, 2 * 60])
        XCTAssertEqual(used.first?.subjects, ["x.com", "reddit.com"])
        XCTAssertEqual(used.last?.subjects, ["Discord"])
    }

    func testConfigurationRoundTrips() throws {
        let url = directory.appendingPathComponent("configuration.json")
        var configuration = AppConfiguration.starter
        configuration.rules.append(RuleTemplate.gambling.make())
        configuration.settings.rulesLockedUntil = date(22, 9)
        try ConfigStore(url: url).save(configuration)
        XCTAssertEqual(try ConfigStore(url: url).load(), configuration)
    }
}
