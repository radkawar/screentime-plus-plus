import Foundation

/// One row in "Apps & Sites": a website when a browser showed one, else the app.
public struct UsageTotal: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var bundleID: String
    public var domain: String?
    public var category: UsageCategory
    public var seconds: TimeInterval
    public var surfaces: [SurfaceTotal]
    public var isDistracting: Bool
}

public struct SurfaceTotal: Sendable, Hashable, Identifiable {
    public var name: String
    public var seconds: TimeInterval
    public var id: String { name }
}

public struct DayTotal: Sendable, Hashable, Identifiable {
    public var day: Date
    public var seconds: TimeInterval
    public var distractingSeconds: TimeInterval
    public var byCategory: [UsageCategory: TimeInterval]
    public var id: Date { day }
}

/// Pure aggregation over clipped segments.
public struct UsageReport: Sendable {
    public let interval: DateInterval
    public let segments: [Segment]

    /// Gap that separates two sessions ("pickups").
    public static let sessionGap: TimeInterval = 60

    public init(segments: [Segment], interval: DateInterval) {
        self.interval = interval
        self.segments = segments.compactMap { $0.clipped(to: interval) }.sorted { $0.start < $1.start }
    }

    public var totalSeconds: TimeInterval { segments.reduce(0) { $0 + $1.duration } }

    public var distractingSeconds: TimeInterval {
        segments.reduce(0) { $0 + ($1.ruleID == nil ? 0 : $1.duration) }
    }

    public var items: [UsageTotal] {
        var totals: [String: UsageTotal] = [:]
        var surfaces: [String: [String: TimeInterval]] = [:]
        for segment in segments {
            let key = segment.domain.map { "site:\($0)" } ?? "app:\(segment.bundleID)"
            var total =
                totals[key]
                ?? UsageTotal(
                    id: key,
                    title: segment.domain ?? segment.appName,
                    bundleID: segment.bundleID,
                    domain: segment.domain,
                    category: segment.category,
                    seconds: 0,
                    surfaces: [],
                    isDistracting: false
                )
            total.seconds += segment.duration
            total.isDistracting = total.isDistracting || segment.ruleID != nil
            totals[key] = total
            if let surface = segment.surface {
                surfaces[key, default: [:]][surface, default: 0] += segment.duration
            }
        }
        return totals.values.map { total in
            var total = total
            total.surfaces = (surfaces[total.id] ?? [:])
                .map { SurfaceTotal(name: $0.key, seconds: $0.value) }
                .sorted { $0.seconds > $1.seconds }
            return total
        }
        .sorted { $0.seconds == $1.seconds ? $0.title < $1.title : $0.seconds > $1.seconds }
    }

    public var byCategory: [(category: UsageCategory, seconds: TimeInterval)] {
        var totals: [UsageCategory: TimeInterval] = [:]
        for segment in segments { totals[segment.category, default: 0] += segment.duration }
        return totals.map { ($0.key, $0.value) }.sorted { $0.seconds > $1.seconds }
    }

    public func byRule() -> [UUID: TimeInterval] {
        var totals: [UUID: TimeInterval] = [:]
        for segment in segments {
            if let id = segment.ruleID { totals[id, default: 0] += segment.duration }
        }
        return totals
    }

    /// Seconds per hour of the interval's first day, split by category.
    public func hourly(calendar: Calendar = .current) -> [[UsageCategory: TimeInterval]] {
        var buckets = Array(repeating: [UsageCategory: TimeInterval](), count: 24)
        let dayStart = calendar.startOfDay(for: interval.start)
        for segment in segments {
            var cursor = segment.start
            while cursor < segment.end {
                let hour = calendar.component(.hour, from: cursor)
                let hourStart = calendar.date(byAdding: .hour, value: hour, to: dayStart) ?? cursor
                let hourEnd = calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? segment.end
                let sliceEnd = min(segment.end, hourEnd)
                guard sliceEnd > cursor else { break }
                if calendar.isDate(cursor, inSameDayAs: dayStart) {
                    buckets[hour][segment.category, default: 0] += sliceEnd.timeIntervalSince(cursor)
                }
                cursor = sliceEnd
            }
        }
        return buckets
    }

    /// Per-day totals for every calendar day in the interval.
    public func daily(calendar: Calendar = .current) -> [DayTotal] {
        var days: [DayTotal] = []
        var dayStart = calendar.startOfDay(for: interval.start)
        while dayStart < interval.end {
            guard let next = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
            let day = DateInterval(start: dayStart, end: next)
            var total = DayTotal(day: dayStart, seconds: 0, distractingSeconds: 0, byCategory: [:])
            for segment in segments where segment.end > day.start && segment.start < day.end {
                guard let clipped = segment.clipped(to: day) else { continue }
                total.seconds += clipped.duration
                if clipped.ruleID != nil { total.distractingSeconds += clipped.duration }
                total.byCategory[clipped.category, default: 0] += clipped.duration
            }
            days.append(total)
            dayStart = next
        }
        return days
    }

    /// Continuous stretches of use, merging gaps shorter than `sessionGap`.
    public var sessions: [DateInterval] {
        var result: [DateInterval] = []
        for segment in segments {
            if let last = result.last, segment.start.timeIntervalSince(last.end) < Self.sessionGap {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, segment.end))
            } else {
                result.append(DateInterval(start: segment.start, end: segment.end))
            }
        }
        return result
    }

    public var longestSession: TimeInterval { sessions.map(\.duration).max() ?? 0 }
}
