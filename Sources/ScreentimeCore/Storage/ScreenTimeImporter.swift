import AppKit
import Foundation

public enum ScreenTimeImportError: LocalizedError {
    case alreadyImported
    case noHistory
    case sourceUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyImported:
            return "You have already imported this Mac’s app history."
        case .noHistory:
            return "No app history is available before your existing recordings within your history retention period. Nothing was imported."
        case .sourceUnavailable(let detail):
            return "Your Mac’s app history could not be read. Allow Screentime++ in System Settings → Privacy & Security → Full Disk Access, then quit and reopen the app. macOS may also have removed or changed this history. (\(detail))"
        }
    }
}

/// Reads only Knowledge's documented-by-research /app/usage intervals. Apple's
/// private store can be stale or absent; it is not the Screen Time report API.
public enum ScreenTimeImporter {
    public static var sourceURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Knowledge/knowledgeC.db")
    }

    public static func read(sourceURL: URL = sourceURL, since: Date, now: Date = Date()) throws -> [Segment] {
        do {
            // A read-only SQLite connection sees committed WAL data without copying
            // a potentially inconsistent database/WAL pair or changing Apple's DB.
            let database = try SQLiteDatabase(path: sourceURL.path, readOnly: true)
            var segments: [Segment] = []
            var names: [String: String] = [:]
            try database.query(
                """
                SELECT o.ZVALUESTRING, o.ZSTARTDATE, o.ZENDDATE
                FROM ZOBJECT o LEFT JOIN ZSOURCE s ON s.Z_PK = o.ZSOURCE
                WHERE o.ZSTREAMNAME = '/app/usage'
                  AND o.ZENDDATE > o.ZSTARTDATE
                  AND o.ZENDDATE > ? AND o.ZSTARTDATE < ?
                  AND (s.ZDEVICEID IS NULL OR s.ZDEVICEID = '')
                ORDER BY o.ZSTARTDATE, o.ZENDDATE, o.Z_PK
                """,
                [.real(since.timeIntervalSinceReferenceDate), .real(now.timeIntervalSinceReferenceDate)]
            ) { row in
                guard let bundleID = row.string(0), !bundleID.isEmpty else { return }
                let rawStart = row.double(1)
                let rawEnd = row.double(2)
                guard rawStart.isFinite, rawEnd.isFinite else { return }
                let start = max(since, Date(timeIntervalSinceReferenceDate: rawStart))
                let end = min(now, Date(timeIntervalSinceReferenceDate: rawEnd))
                guard end > start else { return }
                let name: String
                if let cached = names[bundleID] {
                    name = cached
                } else {
                    name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                        .map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID
                    names[bundleID] = name
                }
                segments.append(Segment(
                    start: start, end: end, bundleID: bundleID, appName: name, domain: nil, surface: nil,
                    category: CategoryCatalog.category(bundleID: bundleID, domain: nil), ruleID: nil))
            }
            return segments
        } catch {
            throw ScreenTimeImportError.sourceUnavailable(String(describing: error))
        }
    }

    @discardableResult
    public static func run(into store: UsageStore, since: Date, now: Date = Date()) throws -> Int {
        guard try !store.hasImportedScreenTime() else { throw ScreenTimeImportError.alreadyImported }
        return try store.importScreenTime(read(since: since, now: now), now: now)
    }
}
