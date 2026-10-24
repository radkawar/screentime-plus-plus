import Foundation

/// Deliberately excludes URLs, page titles, rule names, and the history database.
struct WidgetSnapshot: Codable, Sendable {
    static let groupIdentifier = "3UX5N7Y8TY.dev.screentimepp"
    static let widgetKind = "dev.screentimepp.today"
    static let fileName = "today-widget.json"

    var date: Date
    var distractingSeconds: TimeInterval
    var goalSeconds: TimeInterval
    var totalSeconds: TimeInterval
    var ribbon: [RibbonSegment]
    var topItems: [Item]

    struct Item: Codable, Sendable {
        var title: String
        var seconds: TimeInterval
        var category: String
    }

    /// Seconds since local midnight; category and distracting status travel together.
    struct RibbonSegment: Codable, Sendable {
        var start: TimeInterval
        var end: TimeInterval
        var category: String
        var distracting: Bool

        init(start: TimeInterval, end: TimeInterval, category: String, distracting: Bool) {
            self.start = start
            self.end = end
            self.category = category
            self.distracting = distracting
        }

        init(from decoder: Decoder) throws {
            var values = try decoder.unkeyedContainer()
            start = try values.decode(TimeInterval.self)
            end = try values.decode(TimeInterval.self)
            category = try values.decode(String.self)
            distracting = try values.decode(Bool.self)
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.unkeyedContainer()
            try values.encode(start)
            try values.encode(end)
            try values.encode(category)
            try values.encode(distracting)
        }
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
    }

    static func read(now: Date = Date()) -> WidgetSnapshot? {
        guard let url = containerURL?.appendingPathComponent(fileName),
            let data = try? Data(contentsOf: url),
            let snapshot = try? JSONDecoder().decode(Self.self, from: data)
        else { return nil }
        // Never present yesterday's usage as today's when the host has stopped.
        guard Calendar.current.isDate(snapshot.date, inSameDayAs: now) else { return nil }
        return snapshot
    }

    static var sample: WidgetSnapshot {
        WidgetSnapshot(
            date: Date(), distractingSeconds: 38 * 60, goalSeconds: 60 * 60, totalSeconds: 184 * 60,
            ribbon: [
                .init(start: 9 * 3600, end: 10.5 * 3600, category: "productivity", distracting: false),
                .init(start: 10.5 * 3600, end: 11 * 3600, category: "communication", distracting: false),
                .init(start: 12 * 3600, end: 12.5 * 3600, category: "social", distracting: true),
                .init(start: 14 * 3600, end: 14.75 * 3600, category: "reading", distracting: false),
            ],
            topItems: [
                Item(title: "Xcode", seconds: 90 * 60, category: "productivity"),
                Item(title: "Slack", seconds: 30 * 60, category: "communication"),
                Item(title: "Reddit", seconds: 28 * 60, category: "social"),
            ])
    }
}
