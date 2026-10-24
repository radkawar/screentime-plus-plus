import Foundation

/// A continuous stretch of foreground use of one app/site.
public struct Segment: Sendable, Hashable, Identifiable {
    public var id: Int64
    public var start: Date
    public var end: Date
    public var bundleID: String
    public var appName: String
    public var domain: String?
    public var surface: String?
    public var category: UsageCategory
    /// The first rule whose targets matched, which makes this time "distracting".
    public var ruleID: UUID?

    public init(
        id: Int64 = 0, start: Date, end: Date, bundleID: String, appName: String, domain: String?,
        surface: String?, category: UsageCategory, ruleID: UUID?
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.bundleID = bundleID
        self.appName = appName
        self.domain = domain
        self.surface = surface
        self.category = category
        self.ruleID = ruleID
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    public func clipped(to interval: DateInterval) -> Segment? {
        let start = max(self.start, interval.start)
        let end = min(self.end, interval.end)
        guard end > start else { return nil }
        var copy = self
        copy.start = start
        copy.end = end
        return copy
    }
}

public enum InterventionKind: String, Sendable, Codable {
    case pause
    case block
    case limit
    case focus
}

public enum InterventionOutcome: String, Sendable, Codable {
    /// Still on screen.
    case shown
    /// The user went back, closed the tab, or switched away.
    case turnedBack
    /// The user finished a pause and chose a session.
    case continued
    /// A press-and-hold override.
    case overridden
    /// The tab was closed or the app hidden automatically.
    case closed
}

public struct InterventionRecord: Sendable, Hashable, Identifiable {
    public var id: Int64
    public var at: Date
    public var ruleID: UUID
    public var ruleName: String
    public var kind: InterventionKind
    public var subject: String
    public var outcome: InterventionOutcome
    public var intention: String?

    public init(
        id: Int64 = 0, at: Date, ruleID: UUID, ruleName: String, kind: InterventionKind, subject: String,
        outcome: InterventionOutcome, intention: String? = nil
    ) {
        self.id = id
        self.at = at
        self.ruleID = ruleID
        self.ruleName = ruleName
        self.kind = kind
        self.subject = subject
        self.outcome = outcome
        self.intention = intention
    }
}

public struct RuleDayUsage: Sendable, Hashable {
    public var seconds: TimeInterval
    public var opens: Int

    public init(seconds: TimeInterval = 0, opens: Int = 0) {
        self.seconds = seconds
        self.opens = opens
    }
}

/// Usage history on disk. Stores time, bundle IDs, hosts and surfaces only;
/// never titles, full addresses or page text. Safe to call from any thread.
public final class UsageStore: @unchecked Sendable {
    private let database: SQLiteDatabase
    private let lock = NSLock()

    public init(path: String) throws {
        database = try SQLiteDatabase(path: path)
        try migrate()
    }

    public static func defaultURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = support.appendingPathComponent("Screentime++", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("usage.sqlite")
    }

    private func migrate() throws {
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS segments(
                id INTEGER PRIMARY KEY,
                start REAL NOT NULL,
                end REAL NOT NULL,
                bundle_id TEXT NOT NULL,
                app_name TEXT NOT NULL,
                domain TEXT,
                surface TEXT,
                category TEXT NOT NULL,
                rule_id TEXT
            );
            CREATE INDEX IF NOT EXISTS segments_end ON segments(end);
            CREATE TABLE IF NOT EXISTS interventions(
                id INTEGER PRIMARY KEY,
                at REAL NOT NULL,
                rule_id TEXT NOT NULL,
                rule_name TEXT NOT NULL,
                kind TEXT NOT NULL,
                subject TEXT NOT NULL,
                outcome TEXT NOT NULL,
                intention TEXT
            );
            CREATE INDEX IF NOT EXISTS interventions_at ON interventions(at);
            CREATE TABLE IF NOT EXISTS rule_usage(
                day TEXT NOT NULL,
                rule_id TEXT NOT NULL,
                seconds REAL NOT NULL,
                opens INTEGER NOT NULL,
                PRIMARY KEY(day, rule_id)
            );
            PRAGMA user_version = 1;
            """)
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    // MARK: Segments

    @discardableResult
    public func insert(_ segment: Segment) throws -> Int64 {
        try locked {
            try database.run(
                """
                INSERT INTO segments(start, end, bundle_id, app_name, domain, surface, category, rule_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .real(segment.start.timeIntervalSince1970), .real(segment.end.timeIntervalSince1970),
                    .text(segment.bundleID), .text(segment.appName), .optional(segment.domain),
                    .optional(segment.surface), .text(segment.category.rawValue),
                    .optional(segment.ruleID?.uuidString),
                ])
            return database.lastInsertRowID
        }
    }

    public func updateEnd(segmentID: Int64, end: Date) throws {
        try locked {
            try database.run(
                "UPDATE segments SET end = ? WHERE id = ?", [.real(end.timeIntervalSince1970), .integer(segmentID)])
        }
    }

    /// Segments overlapping `interval`, clipped to it, oldest first.
    public func segments(in interval: DateInterval) throws -> [Segment] {
        try locked {
            var result: [Segment] = []
            try database.query(
                """
                SELECT id, start, end, bundle_id, app_name, domain, surface, category, rule_id
                FROM segments WHERE end > ? AND start < ? ORDER BY start
                """,
                [.real(interval.start.timeIntervalSince1970), .real(interval.end.timeIntervalSince1970)]
            ) { row in
                let segment = Segment(
                    id: row.int(0),
                    start: Date(timeIntervalSince1970: row.double(1)),
                    end: Date(timeIntervalSince1970: row.double(2)),
                    bundleID: row.string(3) ?? "",
                    appName: row.string(4) ?? "",
                    domain: row.string(5),
                    surface: row.string(6),
                    category: UsageCategory(rawValue: row.string(7) ?? "") ?? .other,
                    ruleID: row.string(8).flatMap(UUID.init(uuidString:))
                )
                if let clipped = segment.clipped(to: interval) {
                    result.append(clipped)
                }
            }
            return result
        }
    }

    // MARK: Interventions

    @discardableResult
    public func insert(_ record: InterventionRecord) throws -> Int64 {
        try locked {
            try database.run(
                """
                INSERT INTO interventions(at, rule_id, rule_name, kind, subject, outcome, intention)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .real(record.at.timeIntervalSince1970), .text(record.ruleID.uuidString),
                    .text(record.ruleName), .text(record.kind.rawValue), .text(record.subject),
                    .text(record.outcome.rawValue), .optional(record.intention),
                ])
            return database.lastInsertRowID
        }
    }

    public func update(interventionID: Int64, outcome: InterventionOutcome, intention: String? = nil) throws {
        try locked {
            try database.run(
                "UPDATE interventions SET outcome = ?, intention = COALESCE(?, intention) WHERE id = ?",
                [.text(outcome.rawValue), .optional(intention), .integer(interventionID)])
        }
    }

    public func interventions(in interval: DateInterval) throws -> [InterventionRecord] {
        try locked {
            var result: [InterventionRecord] = []
            try database.query(
                """
                SELECT id, at, rule_id, rule_name, kind, subject, outcome, intention
                FROM interventions WHERE at >= ? AND at < ? ORDER BY at DESC
                """,
                [.real(interval.start.timeIntervalSince1970), .real(interval.end.timeIntervalSince1970)]
            ) { row in
                guard let ruleID = row.string(2).flatMap(UUID.init(uuidString:)) else { return }
                result.append(
                    InterventionRecord(
                        id: row.int(0),
                        at: Date(timeIntervalSince1970: row.double(1)),
                        ruleID: ruleID,
                        ruleName: row.string(3) ?? "",
                        kind: InterventionKind(rawValue: row.string(4) ?? "") ?? .block,
                        subject: row.string(5) ?? "",
                        outcome: InterventionOutcome(rawValue: row.string(6) ?? "") ?? .shown,
                        intention: row.string(7)
                    ))
            }
            return result
        }
    }

    // MARK: Per-rule daily counters

    public func ruleUsage(day: String) throws -> [UUID: RuleDayUsage] {
        try locked {
            var result: [UUID: RuleDayUsage] = [:]
            try database.query("SELECT rule_id, seconds, opens FROM rule_usage WHERE day = ?", [.text(day)]) {
                row in
                guard let id = row.string(0).flatMap(UUID.init(uuidString:)) else { return }
                result[id] = RuleDayUsage(seconds: row.double(1), opens: Int(row.int(2)))
            }
            return result
        }
    }

    public func save(ruleUsage: [UUID: RuleDayUsage], day: String) throws {
        try locked {
            try database.transaction {
                for (id, usage) in ruleUsage {
                    try database.run(
                        """
                        INSERT INTO rule_usage(day, rule_id, seconds, opens) VALUES (?, ?, ?, ?)
                        ON CONFLICT(day, rule_id) DO UPDATE SET seconds = excluded.seconds, opens = excluded.opens
                        """,
                        [.text(day), .text(id.uuidString), .real(usage.seconds), .integer(Int64(usage.opens))])
                }
            }
        }
    }

    // MARK: Maintenance

    public func deleteAll() throws {
        try locked {
            try database.execute("DELETE FROM segments; DELETE FROM interventions; DELETE FROM rule_usage;")
        }
    }

    public func prune(before date: Date) throws {
        let cutoff = date.timeIntervalSince1970
        try locked {
            try database.run("DELETE FROM segments WHERE end < ?", [.real(cutoff)])
            try database.run("DELETE FROM interventions WHERE at < ?", [.real(cutoff)])
        }
    }
}

public enum DayKey {
    public static func string(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
