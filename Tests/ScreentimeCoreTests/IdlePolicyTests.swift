import XCTest
@testable import ScreentimeCore

final class IdlePolicyTests: XCTestCase {
    func testGlobalThresholdAndAssertion() {
        XCTAssertFalse(idle(119))
        XCTAssertTrue(idle(120))
        XCTAssertFalse(idle(120, assertion: true))
        XCTAssertTrue(idle(600))
    }

    func testAlwaysUseOverridesTimeoutWithOrWithoutAssertion() {
        XCTAssertFalse(idle(86_400, override: .alwaysCountsAsUse))
        XCTAssertFalse(idle(86_400, override: .alwaysCountsAsUse, assertion: true))
    }

    func testShorterAppTimeoutOverridesGlobalAndAssertion() {
        XCTAssertFalse(idle(59, override: .idleAfter(minutes: 1)))
        XCTAssertTrue(idle(60, override: .idleAfter(minutes: 1)))
        XCTAssertTrue(idle(60, override: .idleAfter(minutes: 1), assertion: true))
    }

    func testLongerAppTimeoutOverridesGlobalAndAssertion() {
        XCTAssertFalse(idle(120, override: .idleAfter(minutes: 10)))
        XCTAssertFalse(idle(599, override: .idleAfter(minutes: 10), assertion: true))
        XCTAssertTrue(idle(600, override: .idleAfter(minutes: 10), assertion: true))
    }

    func testOverridesDoNotQueryDisplayAssertions() {
        var calls = 0
        func assertion() -> Bool { calls += 1; return true }
        _ = IdlePolicy.isIdle(secondsSinceInput: 500, globalThreshold: 120,
                             override: .idleAfter(minutes: 1), displaySleepIsPrevented: assertion())
        _ = IdlePolicy.isIdle(secondsSinceInput: 500, globalThreshold: 120,
                             override: .alwaysCountsAsUse, displaySleepIsPrevented: assertion())
        _ = IdlePolicy.isIdle(secondsSinceInput: 20, globalThreshold: 120,
                             override: nil, displaySleepIsPrevented: assertion())
        XCTAssertEqual(calls, 0)
    }

    func testOldSettingsDecodeAndOverridesRoundTrip() throws {
        let old = #"{"dailyGoalMinutes":60,"idleThresholdSeconds":120,"inspectsPageText":true,"parksBrowserTabs":true,"retentionDays":90,"hasCompletedSetup":true}"#
        var settings = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        XCTAssertNil(settings.appIdleOverrides)
        settings.appIdleOverrides = ["com.example.player": .alwaysCountsAsUse, "com.example.editor": .idleAfter(minutes: 5)]
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.appIdleOverrides, settings.appIdleOverrides)
    }

    private func idle(_ seconds: TimeInterval, override: AppIdleOverride? = nil, assertion: Bool = false) -> Bool {
        IdlePolicy.isIdle(secondsSinceInput: seconds, globalThreshold: 120,
                          override: override, displaySleepIsPrevented: assertion)
    }
}
