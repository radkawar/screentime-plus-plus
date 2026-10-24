import XCTest

@testable import ScreentimeCore

final class PolicyEngineTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Wednesday 2026-10-21 at the given UTC time.
    private func wednesday(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: hour, minute: minute))!
    }

    private func browser(_ url: String, title: String? = nil) -> ForegroundContext {
        ForegroundContext(
            bundleID: "com.apple.Safari", appName: "Safari", pid: 42, isBrowser: true, url: URL(string: url),
            pageTitle: title)
    }

    private func evaluate(
        _ context: ForegroundContext, _ rules: [Rule], runtime: RuleRuntime = RuleRuntime(),
        content: String? = nil, at date: Date? = nil
    ) -> Evaluation {
        let now = date ?? wednesday(10)
        let page = content.map {
            PageContent(
                text: $0, nodeCount: 1, isPartial: false, capturedAt: now,
                sourceKey: ForegroundReader.sourceKey(context))
        }
        return PolicyEngine.evaluate(
            context: context, content: page, rules: rules, runtime: runtime, now: now, calendar: calendar)
    }

    func testYouTubeWithoutShortsBlocksShortsAndHomeButNotVideos() {
        let rule = RuleTemplate.minimalYouTube.make()
        XCTAssertNotNil(evaluate(browser("https://www.youtube.com/shorts/abc"), [rule]).intervention)
        XCTAssertNotNil(evaluate(browser("https://www.youtube.com/"), [rule]).intervention)
        XCTAssertNil(evaluate(browser("https://www.youtube.com/watch?v=xyz"), [rule]).intervention)
        XCTAssertNil(evaluate(browser("https://www.youtube.com/results?search_query=swift"), [rule]).intervention)
    }

    func testWebsiteTargetCoversSubdomainsButNotLookalikes() {
        let rule = Rule(name: "Reddit", targets: [.website(domain: "reddit.com")], response: .block(BlockSettings()))
        XCTAssertNotNil(evaluate(browser("https://old.reddit.com/r/swift"), [rule]).intervention)
        XCTAssertNil(evaluate(browser("https://notreddit.com/"), [rule]).intervention)
    }

    func testExceptionWinsOverTarget() {
        let rule = Rule(
            name: "Reddit", targets: [.website(domain: "reddit.com")],
            exceptions: [.urlPattern("reddit.com/r/swift*")], response: .block(BlockSettings()))
        XCTAssertNil(evaluate(browser("https://www.reddit.com/r/swift/comments/1"), [rule]).intervention)
        XCTAssertNotNil(evaluate(browser("https://www.reddit.com/r/all"), [rule]).intervention)
    }

    func testContentRuleCountsWholeWordsAcrossTitleAndPageText() {
        let rule = Rule(
            name: "Gambling",
            targets: [.content(ContentRule(phrases: ["casino", "free spins"], minimumMatches: 3))],
            response: .block(BlockSettings()))
        let page = browser("https://example.com/promo", title: "Best Casino")
        // "casinos" and "casinoroyale" are not whole-word matches.
        let below = evaluate(page, [rule], content: "casinos and casinoroyale. FREE   spins")
        XCTAssertNil(below.intervention)
        let at = evaluate(page, [rule], content: "Casino bonus with Free spins")
        guard case .block(let block) = at.intervention, case .phrases(let counts, let total) = block.match.evidence
        else { return XCTFail("expected a phrase block") }
        XCTAssertEqual(total, 3)
        XCTAssertEqual(counts.first?.phrase, "casino")
    }

    func testDiacriticAndCaseInsensitivePhrases() {
        XCTAssertEqual(FoldedText("CAFÉ society, café.").occurrences(of: "cafe"), 2)
    }

    func testTitleScopeIgnoresPageText() {
        let rule = Rule(
            name: "Spoilers",
            targets: [.content(ContentRule(phrases: ["finale"], scope: .titleAndAddress))],
            response: .block(BlockSettings()))
        XCTAssertNil(evaluate(browser("https://example.com/"), [rule], content: "the finale").intervention)
        XCTAssertNotNil(evaluate(browser("https://example.com/", title: "Finale recap"), [rule]).intervention)
    }

    func testPauseEscalatesWithOpensAndIsSkippedDuringSessionGrant() {
        let rule = Rule(
            name: "Social", targets: [.website(domain: "x.com")],
            response: .pause(PauseSettings(waitSeconds: 10, escalationSeconds: 5)))
        let runtime = RuleRuntime(opens: [rule.id: 3])
        guard case .pause(let pause) = evaluate(browser("https://x.com/home"), [rule], runtime: runtime).intervention
        else { return XCTFail("expected pause") }
        XCTAssertEqual(pause.waitSeconds, 25)

        let granted = RuleRuntime(
            opens: [rule.id: 3], grants: [AccessGrant(ruleID: rule.id, until: wednesday(10, 5), kind: .session)])
        XCTAssertNil(evaluate(browser("https://x.com/home"), [rule], runtime: granted).intervention)
        // Expired grant: the pause returns.
        XCTAssertNotNil(
            evaluate(browser("https://x.com/home"), [rule], runtime: granted, at: wednesday(10, 6)).intervention)
    }

    func testPauseWaitIsCapped() {
        XCTAssertEqual(PauseSettings(waitSeconds: 30, escalationSeconds: 30).wait(afterOpens: 50), 120)
    }

    func testMinuteLimitEscalatesTrackToBlock() {
        let rule = Rule(
            name: "News", targets: [.category(.reading)], response: .track, limits: UsageLimits(dailyMinutes: 20))
        let site = browser("https://www.nytimes.com/section/world")
        XCTAssertNil(evaluate(site, [rule], runtime: RuleRuntime(usageSeconds: [rule.id: 1_199])).intervention)
        guard
            case .block(let block) = evaluate(site, [rule], runtime: RuleRuntime(usageSeconds: [rule.id: 1_200]))
                .intervention
        else { return XCTFail("expected limit block") }
        XCTAssertEqual(block.reason, .minutesLimit(20))
    }

    func testOpensLimitBlocksNewOpensButNotACurrentSession() {
        let rule = Rule(
            name: "Social", targets: [.website(domain: "x.com")], response: .pause(PauseSettings()),
            limits: UsageLimits(dailyOpens: 2))
        let exhausted = RuleRuntime(opens: [rule.id: 2])
        guard case .block = evaluate(browser("https://x.com/"), [rule], runtime: exhausted).intervention else {
            return XCTFail("expected opens block")
        }
        let inSession = RuleRuntime(
            opens: [rule.id: 2], grants: [AccessGrant(ruleID: rule.id, until: wednesday(10, 5), kind: .session)])
        XCTAssertNil(evaluate(browser("https://x.com/"), [rule], runtime: inSession).intervention)
    }

    func testScheduleWindowsIncludingOvernight() {
        let work = ScheduleWindow(weekdays: ScheduleWindow.workdays, startMinute: 9 * 60, endMinute: 17 * 60)
        XCTAssertTrue(ScheduleEvaluator.contains(work, date: wednesday(9), calendar: calendar))
        XCTAssertFalse(ScheduleEvaluator.contains(work, date: wednesday(17), calendar: calendar))

        // Tuesday 22:00 to 06:00 covers Wednesday 05:59 but not Wednesday 22:00.
        let night = ScheduleWindow(weekdays: [3], startMinute: 22 * 60, endMinute: 6 * 60)
        XCTAssertTrue(ScheduleEvaluator.contains(night, date: wednesday(5, 59), calendar: calendar))
        XCTAssertFalse(ScheduleEvaluator.contains(night, date: wednesday(6), calendar: calendar))
        XCTAssertFalse(ScheduleEvaluator.contains(night, date: wednesday(22), calendar: calendar))

        let end = ScheduleEvaluator.currentWindowEnd(.windows([work]), at: wednesday(10), calendar: calendar)
        XCTAssertEqual(end, wednesday(17))
    }

    func testFocusOverridesResponseAndLockedFocusIgnoresOverrides() {
        let rule = Rule(name: "Social", targets: [.website(domain: "x.com")], schedule: .duringFocus, response: .track)
        XCTAssertNil(evaluate(browser("https://x.com/"), [rule]).intervention)

        let focus = FocusSession(
            title: "Deep work", start: wednesday(9), end: wednesday(11), ruleIDs: [rule.id], isLocked: true)
        let overridden = RuleRuntime(
            grants: [AccessGrant(ruleID: rule.id, until: wednesday(10, 1), kind: .override)], focus: focus)
        guard case .block(let block) = evaluate(browser("https://x.com/"), [rule], runtime: overridden).intervention
        else { return XCTFail("expected focus block") }
        XCTAssertFalse(block.allowsOverride)
        XCTAssertEqual(block.until, wednesday(11))
        // After the session the rule is dormant again.
        XCTAssertNil(evaluate(browser("https://x.com/"), [rule], runtime: overridden, at: wednesday(11)).intervention)
    }

    func testOverrideGrantSuspendsBlock() {
        let rule = Rule(name: "X", targets: [.website(domain: "x.com")], response: .block(BlockSettings()))
        let runtime = RuleRuntime(grants: [AccessGrant(ruleID: rule.id, until: wednesday(10, 1), kind: .override)])
        XCTAssertNil(evaluate(browser("https://x.com/"), [rule], runtime: runtime).intervention)
    }

    func testStrongestInterventionWins() {
        let pause = Rule(name: "Pause", targets: [.category(.social)], response: .pause(PauseSettings()))
        let block = Rule(name: "Block", targets: [.website(domain: "x.com")], response: .block(BlockSettings()))
        let result = evaluate(browser("https://x.com/home"), [pause, block])
        XCTAssertEqual(result.matches.count, 2)
        guard case .block(let chosen) = result.intervention else { return XCTFail("expected block") }
        XCTAssertEqual(chosen.match.rule.name, "Block")
    }

    func testDisabledRulesNeverMatch() {
        var rule = Rule(name: "X", targets: [.website(domain: "x.com")], response: .block(BlockSettings()))
        rule.isEnabled = false
        XCTAssertEqual(evaluate(browser("https://x.com/"), [rule]), .none)
    }
}
