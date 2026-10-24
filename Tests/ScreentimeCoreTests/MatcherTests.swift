import XCTest

@testable import ScreentimeCore

final class MatcherTests: XCTestCase {
    private func matches(_ pattern: String, _ url: String) -> Bool {
        URLPattern(pattern).matches(URL(string: url)!)
    }

    func testTrailingSlashMeansExactPath() {
        XCTAssertTrue(matches("instagram.com/", "https://www.instagram.com/"))
        XCTAssertFalse(matches("instagram.com/", "https://www.instagram.com/direct/inbox/"))
    }

    func testHostOnlyPatternCoversEverything() {
        XCTAssertTrue(matches("tiktok.com", "https://www.tiktok.com/@someone/video/1"))
        XCTAssertFalse(matches("tiktok.com", "https://example.com/tiktok.com"))
    }

    func testGlobsInPathAndHost() {
        XCTAssertTrue(matches("reddit.com/r/*/comments/*", "https://old.reddit.com/r/swift/comments/abc/title"))
        XCTAssertFalse(matches("reddit.com/r/*/comments/*", "https://reddit.com/r/swift/"))
        XCTAssertTrue(matches("*.substack.com/p/*", "https://someone.substack.com/p/post"))
        XCTAssertTrue(matches("https://YouTube.com/shorts/*", "https://m.youtube.com/shorts/x"))
    }

    func testQueryOnlyMatchedWhenPatternHasOne() {
        XCTAssertTrue(matches("youtube.com/watch*", "https://youtube.com/watch?v=1"))
        XCTAssertTrue(matches("google.com/search?q=*casino*", "https://www.google.com/search?q=best+casino+uk"))
        XCTAssertFalse(matches("google.com/search?q=*casino*", "https://www.google.com/search?q=swift"))
    }

    func testDomainNormalization() {
        XCTAssertEqual(DomainName.normalize(" https://WWW.Example.com./path "), "example.com")
        XCTAssertTrue(DomainName.host("m.youtube.com", isWithin: "youtube.com"))
        XCTAssertFalse(DomainName.host("youtube.com.evil.net", isWithin: "youtube.com"))
    }

    func testCategoryLookupWalksParentDomains() {
        XCTAssertEqual(CategoryCatalog.category(domain: "old.reddit.com"), .social)
        XCTAssertEqual(CategoryCatalog.category(domain: "mail.google.com"), .communication)
        XCTAssertNil(CategoryCatalog.category(domain: "example.org"))
        XCTAssertEqual(CategoryCatalog.category(bundleID: "com.apple.Safari", domain: nil), .other)
    }
}
