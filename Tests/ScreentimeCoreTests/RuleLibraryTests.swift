import XCTest

@testable import ScreentimeCore

final class RuleLibraryTests: XCTestCase {
    func testEveryTemplateIsUsableAndUniquelyNamed() {
        let templates = RuleTemplate.all.filter { $0.id != RuleTemplate.blank.id }
        XCTAssertEqual(Set(templates.map(\.id)).count, templates.count)
        // Packs detect "already added" by rule name, so names must be unique.
        let names = templates.map { $0.make().name }
        XCTAssertEqual(Set(names).count, names.count, "duplicate rule names: \(names)")
        for template in templates {
            XCTAssertFalse(template.make().targets.isEmpty, "\(template.id) has no targets")
        }
    }

    func testPacksOnlyReferenceListedTemplates() {
        let listed = Set(RuleTemplate.all.map(\.id))
        XCTAssertEqual(Set(RulePack.all.map(\.id)).count, RulePack.all.count)
        for pack in RulePack.all {
            XCTAssertFalse(pack.templates.isEmpty)
            for template in pack.templates {
                XCTAssertTrue(listed.contains(template.id), "\(pack.id) uses unlisted \(template.id)")
            }
        }
    }

    /// A phrase that contains another whole phrase from the same rule would be
    /// counted twice for one mention and trip thresholds early.
    func testTemplatePhrasesDoNotOverlap() {
        for template in RuleTemplate.all {
            for case .content(let rule) in template.make().targets {
                for phrase in rule.phrases {
                    for other in rule.phrases where other != phrase {
                        XCTAssertEqual(
                            FoldedText(phrase).occurrences(of: other), 0,
                            "\(template.id): \u{201C}\(phrase)\u{201D} contains \u{201C}\(other)\u{201D}")
                    }
                }
            }
        }
    }

    func testWindDownSpansMidnightAndSparesMusic() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let rule = RuleTemplate.windDown.make()
        let lateNight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 23, minute: 30))!
        let earlyMorning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 6, minute: 59))!
        let afternoon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 15))!
        let youtube = ForegroundContext(
            bundleID: "com.apple.Safari", appName: "Safari", pid: 1, isBrowser: true,
            url: URL(string: "https://www.youtube.com/watch?v=1"))
        let music = ForegroundContext(bundleID: "com.apple.Music", appName: "Music", pid: 2, isBrowser: false)
        func blocked(_ context: ForegroundContext, _ date: Date) -> Bool {
            PolicyEngine.evaluate(
                context: context, content: nil, rules: [rule], runtime: RuleRuntime(), now: date, calendar: calendar
            ).intervention != nil
        }
        XCTAssertTrue(blocked(youtube, lateNight))
        XCTAssertTrue(blocked(youtube, earlyMorning))
        XCTAssertFalse(blocked(youtube, afternoon))
        XCTAssertFalse(blocked(music, lateNight))
    }

    func testSettingsSavedBeforeNewKeysStillDecode() throws {
        let json = #"{"dailyGoalMinutes":60,"idleThresholdSeconds":120,"inspectsPageText":true,"parksBrowserTabs":true,"retentionDays":90,"hasCompletedSetup":true}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertNil(settings.rulesPausedUntil)
        XCTAssertEqual(settings.dailyGoalMinutes, 60)
    }
}
