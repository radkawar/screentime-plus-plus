import XCTest
@testable import ScreentimeCore

final class ExportCodecTests: XCTestCase {
    func testRulePackRoundTrip() throws {
        let rules = RuleTemplate.all.map { $0.make() }
        XCTAssertEqual(try RulePackCodec.decode(RulePackCodec.encode(rules)), rules)
    }

    func testUnknownFieldsAreIgnored() throws {
        let rule = RuleTemplate.mindfulSocial.make()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: RulePackCodec.encode([rule])) as? [String: Any])
        object["futureField"] = ["enabled": true]
        var rules = try XCTUnwrap(object["rules"] as? [[String: Any]])
        rules[0]["futureRuleField"] = 42
        object["rules"] = rules
        XCTAssertEqual(try RulePackCodec.decode(JSONSerialization.data(withJSONObject: object)), [rule])
    }

    func testMalformedRulePackIsRejected() {
        for text in ["not json", "{}", #"{"version":1,"rules":[{}]}"#] {
            XCTAssertThrowsError(try RulePackCodec.decode(Data(text.utf8))) {
                XCTAssertEqual($0 as? RulePackCodec.FileError, .malformed)
            }
        }
    }

    func testFutureVersionIsRejected() {
        XCTAssertThrowsError(try RulePackCodec.decode(Data(#"{"version":2,"rules":[]}"#.utf8))) {
            XCTAssertEqual($0 as? RulePackCodec.FileError, .unsupportedVersion(2))
        }
    }

    func testImportAssignsNewIDsAndSkipsDuplicateNames() {
        let existing = Rule(name: "Existing")
        let new = Rule(name: "New")
        let imported = RulePackCodec.rulesToAdd([existing, new, new], existingNames: [existing.name])
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported.first?.name, new.name)
        XCTAssertNotEqual(imported.first?.id, new.id)
    }

    func testCSVQuotesCommasQuotesAndLineBreaks() {
        let ruleID = UUID()
        let segment = Segment(
            start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 12.5),
            bundleID: "com.example.app", appName: "An \"App\", Inc.", domain: nil,
            surface: "First\r\nSecond", category: .other, ruleID: ruleID)
        let csv = HistoryCSV.encode([segment], ruleNames: [ruleID: "Rule, one"])
        XCTAssertEqual(csv, "start,end,duration_seconds,app,bundle_id,domain,surface,category,rule\r\n"
            + "1970-01-01T00:00:00.000Z,1970-01-01T00:00:12.500Z,12.5,\"An \"\"App\"\", Inc.\",com.example.app,,\"First\r\nSecond\",other,\"Rule, one\"\r\n")
    }
}
