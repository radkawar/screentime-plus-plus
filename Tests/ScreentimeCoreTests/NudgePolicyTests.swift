import XCTest
@testable import ScreentimeCore

final class NudgePolicyTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testContinuousUseAndRepeatCadence() {
        var tracker = TimeNudgeTracker()
        var reminders: [Int] = []
        for seconds in stride(from: 0, through: 5_400, by: 60) {
            if let minutes = tracker.record(subject: "reddit.com", at: date(seconds), idleThreshold: 120) {
                reminders.append(minutes)
            }
        }
        XCTAssertEqual(reminders, [10, 20, 30, 60, 90])
    }

    func testAlternativeCadenceRepeatsThirtyMinutesAfterLastThreshold() {
        var tracker = TimeNudgeTracker()
        var reminders: [Int] = []
        for seconds in stride(from: 0, through: 6_300, by: 60) {
            if let minutes = tracker.record(subject: "reddit.com", at: date(seconds), idleThreshold: 120,
                                            cadence: .fifteenThirtyFortyFive) {
                reminders.append(minutes)
            }
        }
        XCTAssertEqual(reminders, [15, 30, 45, 75, 105])
    }

    func testSubjectChangesStartFreshSession() {
        var tracker = TimeNudgeTracker()
        advance(&tracker, through: 540)
        XCTAssertNil(tracker.record(subject: "x.com", at: date(600), idleThreshold: 120))
        for seconds in stride(from: 660, through: 1_140, by: 60) {
            XCTAssertNil(tracker.record(subject: "x.com", at: date(seconds), idleThreshold: 120))
        }
        XCTAssertEqual(tracker.record(subject: "x.com", at: date(1_200), idleThreshold: 120), 10)
        XCTAssertNil(tracker.record(subject: "reddit.com", at: date(1_201), idleThreshold: 120))
    }

    func testShortAbsencePausesWithoutCountingAwayTime() {
        var tracker = TimeNudgeTracker()
        advance(&tracker, through: 540)
        XCTAssertNil(tracker.record(subject: nil, at: date(541), idleThreshold: 120))
        XCTAssertNil(tracker.record(subject: "reddit.com", at: date(600), idleThreshold: 120))
        XCTAssertEqual(tracker.record(subject: "reddit.com", at: date(660), idleThreshold: 120), 10)
    }

    func testAwayAtIdleThresholdResets() {
        var tracker = TimeNudgeTracker()
        advance(&tracker, through: 540)
        for seconds in [541, 600, 660, 661] {
            XCTAssertNil(tracker.record(subject: nil, at: date(seconds), idleThreshold: 120))
        }
        XCTAssertNil(tracker.record(subject: "reddit.com", at: date(662), idleThreshold: 120))
        XCTAssertNil(tracker.record(subject: "reddit.com", at: date(722), idleThreshold: 120))
    }

    func testSleepSamplingGapAndExplicitIdleReset() {
        var tracker = TimeNudgeTracker()
        advance(&tracker, through: 540)
        XCTAssertNil(tracker.record(subject: "reddit.com", at: date(660), idleThreshold: 120))
        XCTAssertNil(tracker.record(subject: "reddit.com", at: date(720), idleThreshold: 120))
        tracker.reset()
        XCTAssertNil(tracker.record(subject: "reddit.com", at: date(721), idleThreshold: 120))
    }

    func testShieldOrFocusSuppressionResetsWithoutBacklog() {
        var tracker = TimeNudgeTracker()
        advance(&tracker, through: 540)
        XCTAssertNil(tracker.record(subject: "reddit.com", at: date(600), idleThreshold: 120, isSuppressed: true))
        XCTAssertNil(tracker.record(subject: "reddit.com", at: date(601), idleThreshold: 120))
        XCTAssertNil(tracker.record(subject: "reddit.com", at: date(661), idleThreshold: 120))
    }

    func testSessionEndingOncePerGrantAndExtension() {
        var tracker = SessionEndingNudgeTracker()
        let grant = AccessGrant(ruleID: UUID(), until: date(300), kind: .session)
        XCTAssertNil(tracker.reminder(grants: [grant], at: date(179)))
        XCTAssertEqual(tracker.reminder(grants: [grant], at: date(180)), grant)
        XCTAssertNil(tracker.reminder(grants: [grant], at: date(181)))
        let extended = AccessGrant(ruleID: grant.ruleID, until: date(600), kind: .session)
        XCTAssertNil(tracker.reminder(grants: [extended], at: date(181)))
        XCTAssertEqual(tracker.reminder(grants: [extended], at: date(480)), extended)
    }

    func testSessionEndingIgnoresOverrideExpiredLateAndSuppressedGrants() {
        var tracker = SessionEndingNudgeTracker()
        let grant = AccessGrant(ruleID: UUID(), until: date(300), kind: .session)
        let override = AccessGrant(ruleID: UUID(), until: date(300), kind: .override)
        XCTAssertNil(tracker.reminder(grants: [override], at: date(180)))
        XCTAssertNil(tracker.reminder(grants: [grant], at: date(180), isSuppressed: true))
        XCTAssertEqual(tracker.reminder(grants: [grant], at: date(181)), grant)
        XCTAssertNil(tracker.reminder(grants: [grant], at: date(300)))
        var late = SessionEndingNudgeTracker()
        XCTAssertNil(late.reminder(grants: [grant], at: date(240)))
    }

    func testLegacySettingsDefaultOnAndRoundTrip() throws {
        let old = #"{"dailyGoalMinutes":60,"idleThresholdSeconds":120,"inspectsPageText":true,"parksBrowserTabs":true,"retentionDays":90,"hasCompletedSetup":true}"#
        var settings = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        XCTAssertNotEqual(settings.timeNudgesEnabled, false)
        XCTAssertNil(settings.timeNudgeCadence)
        XCTAssertNil(settings.timeNudgesForEverything)
        settings.timeNudgesEnabled = false
        settings.timeNudgeCadence = .fifteenThirtyFortyFive
        settings.timeNudgesForEverything = true
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)), settings)
    }

    private func date(_ seconds: Int) -> Date { start.addingTimeInterval(TimeInterval(seconds)) }

    private func advance(_ tracker: inout TimeNudgeTracker, through end: Int) {
        for seconds in stride(from: 0, through: end, by: 60) {
            XCTAssertNil(tracker.record(subject: "reddit.com", at: date(seconds), idleThreshold: 120))
        }
    }
}
