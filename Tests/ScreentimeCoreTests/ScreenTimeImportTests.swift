import XCTest
@testable import ScreentimeCore

final class ScreenTimeImportTests: XCTestCase {
    private var directory: URL!
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testReadsReferenceDatesClipsRetentionAndExcludesRemoteAndInvalidRows() throws {
        let url = directory.appendingPathComponent("knowledge.db")
        let source = try SQLiteDatabase(path: url.path)
        try source.execute("""
            CREATE TABLE ZSOURCE(Z_PK INTEGER PRIMARY KEY, ZDEVICEID TEXT);
            CREATE TABLE ZOBJECT(Z_PK INTEGER PRIMARY KEY, ZSOURCE INTEGER, ZSTREAMNAME TEXT,
                                 ZVALUESTRING TEXT, ZSTARTDATE REAL, ZENDDATE REAL);
            INSERT INTO ZSOURCE VALUES(1, 'another-device');
            INSERT INTO ZOBJECT VALUES(1, NULL, '/app/usage', 'com.example.local', 800000000, 800000100);
            INSERT INTO ZOBJECT VALUES(2, 1, '/app/usage', 'com.example.remote', 800000100, 800000200);
            INSERT INTO ZOBJECT VALUES(3, NULL, '/app/usage', 'com.example.zero', 800000100, 800000100);
            INSERT INTO ZOBJECT VALUES(4, NULL, '/app/webUsage', 'com.example.web', 800000100, 800000200);
            INSERT INTO ZOBJECT VALUES(5, NULL, '/app/usage', NULL, 800000100, 800000200);
            INSERT INTO ZOBJECT VALUES(6, NULL, '/app/usage', 'com.example.future', 800000300, 800000400);
            """)
        let segments = try ScreenTimeImporter.read(sourceURL: url, since: base.addingTimeInterval(20), now: base.addingTimeInterval(90))
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.start, base.addingTimeInterval(20))
        XCTAssertEqual(segments.first?.end, base.addingTimeInterval(90))
        XCTAssertEqual(segments.first?.bundleID, "com.example.local")
        XCTAssertNil(segments.first?.domain)
        XCTAssertNil(segments.first?.ruleID)
    }

    func testMissingSourceIsNotCreated() {
        let url = directory.appendingPathComponent("missing.db")
        XCTAssertThrowsError(try ScreenTimeImporter.read(sourceURL: url, since: base))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testImportIsOneTimePersistsMarkerAndNeverOverlapsExistingHistory() throws {
        let path = directory.appendingPathComponent("usage.db").path
        let store = try UsageStore(path: path)
        try store.insert(segment(150, 200))
        XCTAssertEqual(try store.importScreenTime([segment(0, 100), segment(80, 180)], now: base.addingTimeInterval(300)), 2)
        let rows = try store.segments(in: DateInterval(start: base, duration: 300))
        XCTAssertEqual(rows.map(\.duration), [100, 50, 50])
        XCTAssertNil(rows[0].domain)
        XCTAssertNil(rows[0].surface)
        XCTAssertNil(rows[0].ruleID)
        XCTAssertEqual(rows[0].category, CategoryCatalog.category(bundleID: "com.apple.Xcode", domain: nil))
        XCTAssertThrowsError(try store.importScreenTime([segment(0, 100)]))
        XCTAssertTrue(try UsageStore(path: path).hasImportedScreenTime())
        try store.deleteAll()
        XCTAssertTrue(try store.hasImportedScreenTime())
        XCTAssertThrowsError(try store.importScreenTime([segment(0, 100)]))
    }

    func testEmptyImportDoesNotConsumeOneTimeMarker() throws {
        let store = try UsageStore(path: directory.appendingPathComponent("usage.db").path)
        XCTAssertThrowsError(try store.importScreenTime([]))
        XCTAssertFalse(try store.hasImportedScreenTime())
        XCTAssertEqual(try store.importScreenTime([segment(0, 10)], now: base.addingTimeInterval(20)), 1)
    }

    func testTransactionFailureRollsBackSegmentsAndMarker() throws {
        let path = directory.appendingPathComponent("usage.db").path
        let store = try UsageStore(path: path)
        let connection = try SQLiteDatabase(path: path)
        try connection.execute("""
            CREATE TRIGGER reject_import_marker BEFORE INSERT ON history_imports
            BEGIN SELECT RAISE(ABORT, 'test failure'); END;
            """)
        XCTAssertThrowsError(try store.importScreenTime([segment(0, 10)], now: base.addingTimeInterval(20)))
        XCTAssertFalse(try store.hasImportedScreenTime())
        XCTAssertTrue(try store.segments(in: DateInterval(start: base, duration: 100)).isEmpty)
        try connection.execute("DROP TRIGGER reject_import_marker")
        XCTAssertEqual(try store.importScreenTime([segment(0, 10)], now: base.addingTimeInterval(20)), 1)
    }

    private func segment(_ start: TimeInterval, _ end: TimeInterval) -> Segment {
        Segment(start: base.addingTimeInterval(start), end: base.addingTimeInterval(end),
                bundleID: "com.apple.Xcode", appName: "Xcode", domain: "example.com", surface: "test",
                category: .other, ruleID: UUID())
    }
}
