import Foundation
import XCTest
@testable import ScreentimeCore

final class RuleDraftTests: XCTestCase {
    func testSurfaceUsesCatalogPatternAndName() {
        let context = ForegroundContext(bundleID: "com.apple.Safari", appName: "Safari", pid: 1,
                                        isBrowser: true, url: URL(string: "https://www.youtube.com/shorts/abc"))
        let rule = RuleDraft.rule(for: DraftSubject(context: context), kind: .pause)
        XCTAssertEqual(rule.targets, [.urlPattern("youtube.com/shorts/*")])
        XCTAssertEqual(rule.name, "YouTube Shorts")
    }

    func testSiteWithoutSurfaceUsesWebsite() {
        let subject = DraftSubject(bundleID: "com.apple.Safari", appName: "Safari", domain: "www.reddit.com")
        let rule = RuleDraft.rule(for: subject, kind: .pause)
        XCTAssertEqual(rule.targets, [.website(domain: "reddit.com")])
        XCTAssertEqual(rule.name, "Reddit")
    }

    func testAppUsesBundleIDAndAppName() {
        let subject = DraftSubject(bundleID: "com.tinyspeck.slackmacgap", appName: "Slack")
        let rule = RuleDraft.rule(for: subject, kind: .pause)
        XCTAssertEqual(rule.targets, [.app(bundleID: subject.bundleID, name: "Slack")])
        XCTAssertEqual(rule.name, "Slack")
    }

    func testKindsUseEditableDefaults() {
        let subject = DraftSubject(bundleID: "com.apple.Safari", appName: "Safari", domain: "reddit.com")
        let pause = RuleDraft.rule(for: subject, kind: .pause)
        XCTAssertEqual(pause.response, .pause(PauseSettings()))
        XCTAssertTrue(pause.limits.isEmpty)
        let limit = RuleDraft.rule(for: subject, kind: .limit)
        XCTAssertEqual(limit.response, .track)
        XCTAssertEqual(limit.limits, UsageLimits(dailyMinutes: 30))
        let block = RuleDraft.rule(for: subject, kind: .block)
        XCTAssertEqual(block.response, .block(BlockSettings(allowsOverride: true)))
        XCTAssertTrue(block.limits.isEmpty)
        XCTAssertNotEqual(pause.id, limit.id)
    }

    func testHistoryTotalDoesNotNarrowToOneSurface() {
        let total = UsageTotal(id: "youtube.com", title: "youtube.com", bundleID: "com.apple.Safari",
                               domain: "youtube.com", category: .entertainment, seconds: 120,
                               surfaces: [SurfaceTotal(name: "Shorts", seconds: 120)], isDistracting: true)
        let subject = DraftSubject(total: total)
        XCTAssertNil(subject.surface)
        XCTAssertEqual(RuleDraft.rule(for: subject, kind: .limit).targets, [.website(domain: "youtube.com")])
    }

    func testUnknownSurfaceFallsBackToSiteAndPreservesUnknownDomain() {
        let subject = DraftSubject(bundleID: "browser", appName: "Browser", domain: "example.org", surface: "Unknown")
        let rule = RuleDraft.rule(for: subject, kind: .block)
        XCTAssertEqual(rule.targets, [.website(domain: "example.org")])
        XCTAssertEqual(rule.name, "example.org")
    }

    func testSurfaceAliasesAreAllCovered() {
        let subject = DraftSubject(bundleID: "browser", appName: "Browser", domain: "instagram.com", surface: "Reels")
        XCTAssertEqual(RuleDraft.rule(for: subject, kind: .pause).targets,
                       [.urlPattern("instagram.com/reels/*"), .urlPattern("instagram.com/reel/*")])
    }
}
