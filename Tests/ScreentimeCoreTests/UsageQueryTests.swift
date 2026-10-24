import XCTest
@testable import ScreentimeCore

final class UsageQueryTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func segment(_ bundle: String, domain: String? = nil, surface: String? = nil, day: Int = 21) -> Segment {
        Segment(start: date(day, 10), end: date(day, 11), bundleID: bundle, appName: bundle,
                domain: domain, surface: surface, category: .entertainment, ruleID: nil)
    }

    func testSiteQueryCombinesBrowsersButNotSubdomainsOrOtherSites() {
        let report = UsageReport(segments: [
            segment("safari", domain: "youtube.com", surface: "Shorts"),
            segment("chrome", domain: "youtube.com", surface: "Watch", day: 22),
            segment("safari", domain: "music.youtube.com"),
            segment("safari", domain: "reddit.com"),
            segment("safari"),
        ], interval: DateInterval(start: date(21), end: date(24)))
        let subject = DraftSubject(bundleID: "safari", appName: "Safari", domain: "www.YouTube.com")
        let filtered = report.filtered(for: subject)
        XCTAssertEqual(filtered.totalSeconds, 7200)
        XCTAssertEqual(filtered.interval, report.interval)
        XCTAssertEqual(filtered.daily(calendar: calendar).map(\.seconds), [3600, 3600, 0])
        XCTAssertEqual(Set(filtered.items.flatMap(\.surfaces).map(\.name)), ["Shorts", "Watch"])
    }

    func testAppQueryMatchesItsRowNotAttributedWebsiteTime() {
        let report = UsageReport(segments: [segment("safari"), segment("safari", domain: "youtube.com"), segment("other")],
                                 interval: DateInterval(start: date(21), end: date(22)))
        let subject = DraftSubject(bundleID: "safari", appName: "Safari")
        XCTAssertEqual(report.filtered(for: subject).totalSeconds, 3600)
        XCTAssertEqual(report.filtered(for: DraftSubject(bundleID: "missing", appName: "Missing")).totalSeconds, 0)
    }

    func testSurfaceQueryExcludesOtherSurfaces() {
        let report = UsageReport(segments: [
            segment("safari", domain: "youtube.com", surface: "Shorts"),
            segment("chrome", domain: "youtube.com", surface: "Watch"),
        ], interval: DateInterval(start: date(21), end: date(22)))
        let subject = DraftSubject(bundleID: "safari", appName: "Safari", domain: "youtube.com", surface: "Shorts")
        XCTAssertEqual(report.filtered(for: subject).totalSeconds, 3600)
        XCTAssertEqual(report.filtered(for: subject).items.first?.surfaces.map(\.name), ["Shorts"])
    }

    func testDayQueryClipsMidnightAndRetainsEmptyDay() {
        let segment = Segment(start: date(21, 23), end: date(22, 1), bundleID: "app", appName: "App",
                              domain: nil, surface: nil, category: .productivity, ruleID: UUID())
        let report = UsageReport(segments: [segment], interval: DateInterval(start: date(21), end: date(24)))
        let day = report.on(day: date(22, 12), calendar: calendar)
        XCTAssertEqual(day.interval, DateInterval(start: date(22), end: date(23)))
        XCTAssertEqual(day.totalSeconds, 3600)
        XCTAssertEqual(day.distractingSeconds, 3600)
        XCTAssertEqual(report.on(day: date(23), calendar: calendar).totalSeconds, 0)
    }
}
