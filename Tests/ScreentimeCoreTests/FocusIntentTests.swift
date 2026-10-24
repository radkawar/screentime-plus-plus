import XCTest
@testable import ScreentimeCore

final class FocusIntentTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(_ hour: Int, _ minute: Int = 0, day: Int = 21) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func evaluate(_ session: FocusSession, url: String = "https://reddit.com/", grants: [AccessGrant] = [],
                          at now: Date? = nil) -> Evaluation {
        PolicyEngine.evaluate(context: ForegroundContext(bundleID: "com.apple.Safari", appName: "Safari", pid: 42,
                                                         isBrowser: true, url: URL(string: url)),
                              content: nil, rules: [], runtime: RuleRuntime(grants: grants, focus: session),
                              now: now ?? date(10), calendar: calendar)
    }

    func testCategoriesBlockWithoutAnyRules() {
        let focus = FocusProfile(name: "Writing", categories: [.social]).session(start: date(9), end: date(11))
        guard case .block(let block) = evaluate(focus).intervention else { return XCTFail("Expected Focus block") }
        XCTAssertEqual(block.match.rule.id, focus.id)
        XCTAssertEqual(block.reason, .focus(title: "Writing", until: date(11), locked: false))
        XCTAssertTrue(block.allowsOverride)
        XCTAssertNil(evaluate(focus, url: "https://swift.org/").intervention)
        XCTAssertNil(evaluate(focus, at: date(11)).intervention)
        XCTAssertNil(evaluate(focus, at: date(8)).intervention)
    }

    func testTargetBlocksOnlyChosenSurface() {
        let focus = FocusProfile(name: "Study", categories: [], targets: [.urlPattern("youtube.com/shorts/*")])
            .session(start: date(9), end: date(11))
        XCTAssertNotNil(evaluate(focus, url: "https://youtube.com/shorts/abc").intervention)
        XCTAssertNil(evaluate(focus, url: "https://youtube.com/watch?v=abc").intervention)
    }

    func testAppTargetBlocksWithoutSavedRule() {
        let focus = FocusProfile(name: "Writing", categories: [], targets: [.app(bundleID: "com.example.chat", name: "Chat")])
            .session(start: date(9), end: date(11))
        let result = PolicyEngine.evaluate(context: ForegroundContext(bundleID: "com.example.chat", appName: "Chat", pid: 1, isBrowser: false),
                                           content: nil, rules: [], runtime: RuleRuntime(focus: focus), now: date(10))
        XCTAssertNotNil(result.intervention)
    }

    func testLockedCategoriesIgnoreOverridesAndPauseGrants() {
        var focus = FocusProfile(name: "Writing", categories: [.social]).session(start: date(9), end: date(11))
        let override = AccessGrant(ruleID: focus.id, until: date(10, 5), kind: .override)
        XCTAssertNil(evaluate(focus, grants: [override]).intervention)
        XCTAssertNotNil(evaluate(focus, grants: [AccessGrant(ruleID: focus.id, until: date(10, 5), kind: .session)]).intervention)
        focus.isLocked = true
        guard case .block(let block) = evaluate(focus, grants: [override]).intervention else {
            return XCTFail("Locked Focus must ignore overrides")
        }
        XCTAssertFalse(block.allowsOverride)
    }

    func testOldFocusSessionJSONDecodesAndStillBlocksRule() throws {
        let rule = Rule(name: "Social", targets: [.website(domain: "reddit.com")], schedule: .duringFocus, response: .track)
        let old = """
        {"id":"00000000-0000-0000-0000-000000000001","title":"Old Focus",
         "start":"2026-10-21T09:00:00Z","end":"2026-10-21T11:00:00Z",
         "ruleIDs":["\(rule.id.uuidString)"],"isLocked":true}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let focus = try decoder.decode(FocusSession.self, from: Data(old.utf8))
        XCTAssertNil(focus.categories)
        XCTAssertNil(focus.targets)
        XCTAssertNil(focus.automationID)
        let result = PolicyEngine.evaluate(context: ForegroundContext(bundleID: "com.apple.Safari", appName: "Safari", pid: 1,
                                                                     isBrowser: true, url: URL(string: "https://reddit.com")),
                                           content: nil, rules: [rule], runtime: RuleRuntime(focus: focus), now: date(10))
        guard case .block(let block) = result.intervention else { return XCTFail("Expected legacy rule focus") }
        XCTAssertFalse(block.allowsOverride)
    }

    func testOldConfigurationDecodesWithoutProfiles() throws {
        let encoded = try JSONEncoder().encode(AppConfiguration())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "focusProfiles")
        object.removeValue(forKey: "defaultFocusProfileID")
        let config = try JSONDecoder().decode(AppConfiguration.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(config.focusProfiles)
        XCTAssertNil(config.defaultFocusProfileID)
    }

    func testScheduledFocusUsesWindowEndAndDoesNotRestart() {
        var profile = FocusProfile(name: "Writing", windows: [ScheduleWindow(weekdays: [4], startMinute: 9 * 60, endMinute: 11 * 60)])
        XCTAssertEqual(FocusAutomation.decision(profiles: [profile], current: nil, now: date(8), calendar: calendar), .none)
        guard case .start(let id, let occurrence, let end) = FocusAutomation.decision(profiles: [profile], current: nil,
                                                                                    now: date(9), calendar: calendar)
        else { return XCTFail("Expected automatic start") }
        XCTAssertEqual(id, profile.id)
        XCTAssertEqual(end, date(11))
        profile.consumedOccurrences = [occurrence: end]
        XCTAssertEqual(FocusAutomation.decision(profiles: [profile], current: nil, now: date(10), calendar: calendar), .none)
        XCTAssertEqual(FocusAutomation.decision(profiles: [profile], current: nil, now: date(11), calendar: calendar), .none)
        guard case .start = FocusAutomation.decision(profiles: [profile], current: nil, now: date(9, day: 28), calendar: calendar)
        else { return XCTFail("Next week's occurrence should start") }
    }

    func testOvernightAndAllDayWindows() {
        let overnight = FocusProfile(name: "Night", windows: [ScheduleWindow(weekdays: [3], startMinute: 22 * 60, endMinute: 6 * 60)])
        guard case .start(_, _, let end) = FocusAutomation.decision(profiles: [overnight], current: nil, now: date(5), calendar: calendar)
        else { return XCTFail("Expected overnight start") }
        XCTAssertEqual(end, date(6))
        let allDay = FocusProfile(name: "Day", windows: [ScheduleWindow(weekdays: [4], startMinute: 0, endMinute: 0)])
        guard case .start(_, _, let dayEnd) = FocusAutomation.decision(profiles: [allDay], current: nil, now: date(10), calendar: calendar)
        else { return XCTFail("Expected all-day start") }
        XCTAssertEqual(dayEnd, date(0, day: 22))
    }

    func testAutomationNeverReplacesManualOrLockedSession() {
        let profile = FocusProfile(name: "Writing", windows: [ScheduleWindow(weekdays: [4], startMinute: 9 * 60, endMinute: 11 * 60)])
        let manual = profile.session(start: date(9), end: date(12))
        XCTAssertEqual(FocusAutomation.decision(profiles: [profile], current: manual, now: date(10), calendar: calendar), .none)
        var locked = manual
        locked.isLocked = true
        locked.automationID = "removed-event"
        XCTAssertEqual(FocusAutomation.decision(profiles: [], current: locked, now: date(10), calendar: calendar), .none)
        locked.isLocked = false
        XCTAssertEqual(FocusAutomation.decision(profiles: [], current: locked, now: date(10), calendar: calendar), .stop)
    }

    func testCalendarStartsAndStopsAtEventBoundaries() {
        let profile = FocusProfile(name: "Writing", calendarTitleContains: "Writing")
        var event = FocusCalendarOccurrence(id: "event", profileID: profile.id, start: date(10), end: date(11))
        XCTAssertEqual(FocusAutomation.decision(profiles: [profile], current: nil, events: [event], now: date(9), calendar: calendar), .none)
        guard case .start(_, let occurrence, let end) = FocusAutomation.decision(profiles: [profile], current: nil,
                                                                                events: [event], now: date(10), calendar: calendar)
        else { return XCTFail("Expected event start") }
        XCTAssertEqual(end, date(11))
        let focus = profile.session(start: date(10), end: end, automationID: occurrence)
        XCTAssertEqual(FocusAutomation.decision(profiles: [profile], current: focus, events: [], now: date(10, 5), calendar: calendar), .stop)
        event.end = date(12)
        XCTAssertEqual(FocusAutomation.decision(profiles: [profile], current: focus, events: [event], now: date(10, 5), calendar: calendar), .updateEnd(date(12)))
        XCTAssertEqual(FocusAutomation.decision(profiles: [profile], current: nil, events: [event], now: date(12), calendar: calendar), .none)
    }

    func testSavedProfileOrderWinsAndEmptyProfilesDoNotStart() {
        let window = ScheduleWindow(weekdays: [4], startMinute: 9 * 60, endMinute: 11 * 60)
        let empty = FocusProfile(name: "Empty", categories: [], windows: [window])
        let first = FocusProfile(name: "Writing", windows: [window])
        let second = FocusProfile(name: "Study", windows: [window])
        guard case .start(let id, _, _) = FocusAutomation.decision(profiles: [empty, first, second], current: nil,
                                                                  now: date(10), calendar: calendar)
        else { return XCTFail("Expected selected profile") }
        XCTAssertEqual(id, first.id)
    }
}
