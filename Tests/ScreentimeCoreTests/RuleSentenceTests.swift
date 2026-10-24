import XCTest
@testable import ScreentimeCore

final class RuleSentenceTests: XCTestCase {
    private func rule(response: Response = .track, limits: UsageLimits = UsageLimits()) -> Rule {
        Rule(name: "Reddit", targets: [.website(domain: "reddit.com")], response: response, limits: limits)
    }

    func testTrackWithoutLimits() {
        XCTAssertEqual(RuleSentence(rule: rule()).text, "When you open reddit.com any time, track your time.")
        XCTAssertNil(RuleSentence(rule: rule()).limits)
    }

    func testPauseEscalationAndFixedWait() {
        XCTAssertEqual(RuleSentence(rule: rule(response: .pause(PauseSettings()))).response, "pause 10s, 5s longer each open")
        XCTAssertEqual(
            RuleSentence(rule: rule(response: .pause(PauseSettings(waitSeconds: 20, escalationSeconds: 0)))).response,
            "pause 20s each open")
    }

    func testEveryResponseAndLimitCombination() {
        let responses: [Response] = [.track, .pause(PauseSettings()), .block(BlockSettings())]
        let limits = [UsageLimits(), UsageLimits(dailyMinutes: 45), UsageLimits(dailyOpens: 1), UsageLimits(dailyMinutes: 45, dailyOpens: 10)]
        let endings: [String?] = [nil, "stop after 45 min a day", "stop after 1 open a day", "stop after 45 min or 10 opens a day"]
        for response in responses {
            for (index, limit) in limits.enumerated() {
                let sentence = RuleSentence(rule: rule(response: response, limits: limit))
                XCTAssertEqual(sentence.limits, endings[index])
                XCTAssertTrue(sentence.text.hasSuffix("."))
                XCTAssertFalse(sentence.text.contains("  "))
                if let ending = endings[index] { XCTAssertTrue(sentence.text.contains(" and \(ending).")) }
            }
        }
    }

    func testBlockOptionsAreExplicit() {
        XCTAssertEqual(RuleSentence(rule: rule(response: .block(BlockSettings()))).response, "block access, with a one-minute override")
        XCTAssertEqual(
            RuleSentence(rule: rule(response: .block(BlockSettings(allowsOverride: false, closesAutomatically: true)))).response,
            "block access, without overrides, and close the tab or app")
    }

    func testFocusAndOvernightSchedules() {
        var value = rule()
        value.schedule = .duringFocus
        XCTAssertEqual(RuleSentence(rule: value).schedule, "during Focus")
        value.schedule = .windows([ScheduleWindow(weekdays: ScheduleWindow.everyDay, startMinute: 1320, endMinute: 420)])
        XCTAssertEqual(RuleSentence(rule: value).schedule, "every day from 22:00 to 07:00 the next day")
        value.schedule = .windows([ScheduleWindow(weekdays: [2], startMinute: 540, endMinute: 540)])
        XCTAssertEqual(RuleSentence(rule: value).schedule, "on Mon from 09:00 to 09:00 the next day")
    }

    func testMultipleWindowsAndEmptySchedules() {
        var value = rule()
        value.schedule = .windows([
            ScheduleWindow(weekdays: ScheduleWindow.workdays, startMinute: 540, endMinute: 1020),
            ScheduleWindow(weekdays: [1, 7], startMinute: 600, endMinute: 720),
        ])
        XCTAssertEqual(RuleSentence(rule: value).schedule, "on weekdays from 09:00 to 17:00; or on weekends from 10:00 to 12:00")
        value.schedule = .windows([])
        XCTAssertEqual(RuleSentence(rule: value).schedule, "on no scheduled days")
        value.schedule = .windows([ScheduleWindow(weekdays: [], startMinute: 540, endMinute: 600)])
        XCTAssertEqual(RuleSentence(rule: value).schedule, "on no days from 09:00 to 10:00")
    }

    func testContentAndExceptions() {
        var value = rule()
        value.targets = [.content(ContentRule(phrases: ["casino"]))]
        value.exceptions = [.website(domain: "example.com")]
        XCTAssertEqual(RuleSentence(rule: value).text, "When you open pages that mention “casino”, except example.com, any time, track your time.")
        value.targets = [.content(ContentRule(phrases: ["casino", "betting"], minimumMatches: 3, scope: .titleAndAddress, apps: ["com.example.browser"]))]
        XCTAssertEqual(RuleSentence(rule: value).subject, "pages that mention “casino” or “betting” in the title or address at least 3 times in total inside com.example.browser")
    }

    func testMixedTargetsAndEmptyDraft() {
        var value = rule()
        value.targets = [.app(bundleID: "com.example.app", name: "Slack"), .urlPattern("youtube.com/shorts/*"), .category(.social)]
        XCTAssertEqual(RuleSentence(rule: value).subject, "Slack, pages at youtube.com/shorts/*, or social apps and sites")
        value.targets = []
        XCTAssertEqual(RuleSentence(rule: value).subject, "an app or site")
    }

    func testCategoriesShareOnePhraseAndAppsUseNames() {
        let value = Rule(
            name: "Mixed",
            targets: [
                .category(.social), .website(domain: "reddit.com"), .category(.games),
                .content(ContentRule(phrases: ["random"], scope: .titleAndAddress, apps: ["com.tinyspeck.slackmacgap"])),
            ])
        let subject = RuleSentence(rule: value).subject
        XCTAssertTrue(subject.hasPrefix("social or games apps and sites, reddit.com"), subject)
        XCTAssertTrue(subject.hasSuffix("inside Slack"), subject)
    }
}
