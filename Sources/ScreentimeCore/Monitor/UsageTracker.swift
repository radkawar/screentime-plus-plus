import Foundation

/// Turns once-a-second samples into stored segments and per-rule daily
/// counters. Not thread-safe; drive it from one actor.
public final class UsageTracker {
    /// Samples further apart than this are not treated as continuous use.
    public static let continuityLimit: TimeInterval = 3
    /// Away from a rule's targets for this long makes the next entry an "open".
    public static let reopenGap: TimeInterval = 60

    private let store: UsageStore
    private let calendar: Calendar
    private var open: Segment?
    private var lastPersistedEnd: Date?
    private var lastSampleAt: Date?
    private var lastEntryAt: [UUID: Date] = [:]
    private var lastCounterSave: Date?
    private var countersDirty = false

    public private(set) var day: String
    public private(set) var ruleUsage: [UUID: RuleDayUsage]

    public init(store: UsageStore, calendar: Calendar = .current, now: Date = Date()) {
        self.store = store
        self.calendar = calendar
        day = DayKey.string(for: now, calendar: calendar)
        ruleUsage = (try? store.ruleUsage(day: day)) ?? [:]
    }

    /// Record one sample. `context` nil means idle, away, or Screentime++ itself.
    /// Shielded time is not use: it closes the segment and adds nothing.
    public func record(context: ForegroundContext?, matches: [RuleMatch], isShielded: Bool, at now: Date) {
        rollOverIfNeeded(now)
        let previous = lastSampleAt
        lastSampleAt = now
        guard let context, !isShielded else {
            close(at: previous ?? now)
            saveCountersIfDue(now, force: false)
            return
        }
        let continuous = previous.map { now.timeIntervalSince($0) <= Self.continuityLimit } ?? false
        let delta = continuous ? now.timeIntervalSince(previous!) : 0

        let ruleID = matches.first?.rule.id
        if var segment = open, continuous, segment.bundleID == context.bundleID,
            segment.domain == context.domain, segment.surface == context.surface, segment.ruleID == ruleID
        {
            segment.end = now
            open = segment
            persistEndIfDue(now)
        } else {
            let start = continuous ? (previous ?? now) : now
            close(at: continuous ? start : (previous ?? now))
            begin(
                Segment(
                    start: start, end: now, bundleID: context.bundleID, appName: context.appName,
                    domain: context.domain, surface: context.surface, category: context.category,
                    ruleID: ruleID))
        }

        for match in matches {
            let id = match.rule.id
            var usage = ruleUsage[id] ?? RuleDayUsage()
            usage.seconds += delta
            let away = lastEntryAt[id].map { now.timeIntervalSince($0) > Self.reopenGap } ?? true
            if away, !match.rule.countsOpensOnContinue {
                usage.opens += 1
            }
            lastEntryAt[id] = now
            ruleUsage[id] = usage
            countersDirty = true
        }
        saveCountersIfDue(now, force: false)
    }

    /// A pause finished and the user chose to continue.
    public func registerOpen(ruleID: UUID, at now: Date) {
        rollOverIfNeeded(now)
        ruleUsage[ruleID, default: RuleDayUsage()].opens += 1
        lastEntryAt[ruleID] = now
        countersDirty = true
        saveCountersIfDue(now, force: true)
    }

    public func flush(at now: Date = Date()) {
        if let open {
            try? store.updateEnd(segmentID: open.id, end: open.end)
            lastPersistedEnd = open.end
        }
        saveCountersIfDue(now, force: true)
    }

    // MARK: Private

    private func begin(_ segment: Segment) {
        var segment = segment
        segment.id = (try? store.insert(segment)) ?? 0
        open = segment
        lastPersistedEnd = segment.end
    }

    private func close(at end: Date) {
        guard var segment = open else { return }
        segment.end = max(segment.start, min(segment.end, end))
        if segment.id != 0 {
            try? store.updateEnd(segmentID: segment.id, end: segment.end)
        }
        open = nil
        lastPersistedEnd = nil
    }

    private func persistEndIfDue(_ now: Date) {
        guard let open, open.id != 0 else { return }
        if let lastPersistedEnd, now.timeIntervalSince(lastPersistedEnd) < 10 { return }
        try? store.updateEnd(segmentID: open.id, end: open.end)
        lastPersistedEnd = open.end
    }

    private func saveCountersIfDue(_ now: Date, force: Bool) {
        guard countersDirty else { return }
        if !force, let lastCounterSave, now.timeIntervalSince(lastCounterSave) < 15 { return }
        try? store.save(ruleUsage: ruleUsage, day: day)
        lastCounterSave = now
        countersDirty = false
    }

    private func rollOverIfNeeded(_ now: Date) {
        let today = DayKey.string(for: now, calendar: calendar)
        guard today != day else { return }
        // Split a segment that runs across midnight.
        let midnight = calendar.startOfDay(for: now)
        if var segment = open, segment.start < midnight {
            let tail = segment
            segment.end = min(segment.end, midnight)
            if segment.id != 0 { try? store.updateEnd(segmentID: segment.id, end: segment.end) }
            open = nil
            if tail.end > midnight {
                var next = tail
                next.start = midnight
                begin(next)
            }
        }
        saveCountersIfDue(now, force: true)
        day = today
        ruleUsage = (try? store.ruleUsage(day: today)) ?? [:]
        lastEntryAt = [:]
    }
}

extension Rule {
    /// Pause rules count an open when a pause is completed, not on entry.
    var countsOpensOnContinue: Bool {
        if case .pause = response { return true }
        return false
    }
}
