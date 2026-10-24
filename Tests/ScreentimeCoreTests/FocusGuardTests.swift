import XCTest
@testable import ScreentimeCore

final class FocusGuardTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func focus(locked: Bool = true) -> FocusSession {
        FocusSession(title: "Focus", start: start, end: start.addingTimeInterval(60), ruleIDs: [UUID()], isLocked: locked)
    }

    func testLockedFocusRelaunchesOnlyWhenAppIsMissing() {
        XCTAssertEqual(FocusGuardDecision.evaluate(focus: focus(), appIsRunning: false, at: start), .relaunch)
        XCTAssertEqual(FocusGuardDecision.evaluate(focus: focus(), appIsRunning: true, at: start), .wait)
    }

    func testNoFocusAndUnlockedFocusStopGuard() {
        XCTAssertEqual(FocusGuardDecision.evaluate(focus: nil, appIsRunning: false, at: start), .stop)
        XCTAssertEqual(FocusGuardDecision.evaluate(focus: focus(locked: false), appIsRunning: false, at: start), .stop)
    }

    func testExpiredAndFutureFocusNeverRelaunch() {
        XCTAssertEqual(FocusGuardDecision.evaluate(focus: focus(), appIsRunning: false, at: start.addingTimeInterval(60)), .stop)
        XCTAssertEqual(FocusGuardDecision.evaluate(focus: focus(), appIsRunning: false, at: start.addingTimeInterval(-1)), .stop)
        XCTAssertEqual(FocusGuardDecision.evaluate(focus: focus(), appIsRunning: true, at: start.addingTimeInterval(61)), .stop)
    }
}
