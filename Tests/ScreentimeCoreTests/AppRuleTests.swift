import XCTest

@testable import ScreentimeCore

final class AppRuleTests: XCTestCase {
    private let slack = ForegroundContext(
        bundleID: "com.tinyspeck.slackmacgap", appName: "Slack", pid: 7, isBrowser: false,
        windowTitle: "random (Channel) - Acme - Slack")
    private let discord = ForegroundContext(
        bundleID: "com.hnc.Discord", appName: "Discord", pid: 8, isBrowser: false, windowTitle: "#random | Friends")

    private func intervention(_ context: ForegroundContext, _ rule: Rule) -> Intervention? {
        PolicyEngine.evaluate(
            context: context, content: nil, rules: [rule], runtime: RuleRuntime(), now: Date()
        ).intervention
    }

    func testPhraseScopedToOneAppIgnoresOtherApps() {
        let rule = Rule(
            name: "Slack #random",
            targets: [
                .content(
                    ContentRule(
                        phrases: ["random"], scope: .titleAndAddress, apps: ["com.tinyspeck.slackmacgap"]))
            ],
            response: .block(BlockSettings()))
        XCTAssertNotNil(intervention(slack, rule))
        XCTAssertNil(intervention(discord, rule))
    }

    func testAppTargetWithChannelException() {
        let rule = Rule(
            name: "Slack",
            targets: [.app(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")],
            exceptions: [.content(ContentRule(phrases: ["eng-oncall"], scope: .titleAndAddress))],
            response: .block(BlockSettings()))
        XCTAssertNotNil(intervention(slack, rule))
        var oncall = slack
        oncall.windowTitle = "eng-oncall (Channel) - Acme - Slack"
        XCTAssertNil(intervention(oncall, rule))
    }

    func testDeclaredAppCategories() {
        XCTAssertEqual(DeclaredAppCategory.category(declared: "public.app-category.games"), .games)
        XCTAssertEqual(DeclaredAppCategory.category(declared: "public.app-category.strategy-games"), .games)
        XCTAssertEqual(DeclaredAppCategory.category(declared: "public.app-category.social-networking"), .social)
        XCTAssertEqual(DeclaredAppCategory.category(declared: "public.app-category.developer-tools"), .productivity)
        XCTAssertNil(DeclaredAppCategory.category(declared: "public.app-category.lifestyle"))
    }

    func testContentRulesSavedBeforeAppScopingStillDecode() throws {
        let json = #"{"phrases":["casino"],"minimumMatches":2,"scope":"pageText"}"#
        let rule = try JSONDecoder().decode(ContentRule.self, from: Data(json.utf8))
        XCTAssertEqual(rule.apps, [])
        XCTAssertEqual(rule.minimumMatches, 2)
    }
}
