import Foundation

public enum TimeNudgeCadence: String, Codable, CaseIterable, Sendable {
    case tenTwentyThirty
    case fifteenThirtyFortyFive

    public var title: String {
        switch self {
        case .tenTwentyThirty: "10, 20, 30 Minutes"
        case .fifteenThirtyFortyFive: "15, 30, 45 Minutes"
        }
    }

    private var step: Int { self == .tenTwentyThirty ? 10 : 15 }

    func milestone(at seconds: TimeInterval) -> Int? {
        let minutes = Int(seconds / 60)
        guard minutes >= step else { return nil }
        let lastInitial = step * 3
        if minutes < lastInitial { return (minutes / step) * step }
        return lastInitial + ((minutes - lastInitial) / 30) * 30
    }
}

/// Counts only consecutive foreground samples. Short absences pause the clock;
/// an absence or sampling gap reaching the idle threshold starts a new session.
public struct TimeNudgeTracker: Sendable {
    private var subject: String?
    private var previousSample: Date?
    private var absentSince: Date?
    private var elapsed: TimeInterval = 0
    private var lastMilestone = 0
    private var cadence: TimeNudgeCadence?

    public init() {}

    public mutating func reset() {
        self = Self()
    }

    /// A nil subject means away, not a new subject. A shield or an explicit idle
    /// sample resets immediately because neither is continuous use.
    public mutating func record(
        subject current: String?, at now: Date, idleThreshold: TimeInterval,
        cadence: TimeNudgeCadence = .tenTwentyThirty, isSuppressed: Bool = false
    ) -> Int? {
        if isSuppressed {
            reset()
            return nil
        }
        if let previousSample,
            now < previousSample || now.timeIntervalSince(previousSample) >= idleThreshold {
            reset()
        }
        guard let current else {
            if absentSince == nil { absentSince = now }
            if let absentSince, now.timeIntervalSince(absentSince) >= idleThreshold {
                reset()
            }
            previousSample = now
            return nil
        }
        if current != subject || self.cadence != cadence
            || absentSince.map({ now.timeIntervalSince($0) >= idleThreshold }) == true {
            reset()
            subject = current
            self.cadence = cadence
        } else if absentSince == nil, let previousSample {
            elapsed += now.timeIntervalSince(previousSample)
        }
        previousSample = now
        absentSince = nil
        guard let milestone = cadence.milestone(at: elapsed), milestone > lastMilestone else { return nil }
        lastMilestone = milestone
        return milestone
    }
}

/// A grant is identified by its rule and expiry, like the persisted notification
/// identity. Extending a grant therefore creates a new reminder opportunity.
public struct SessionEndingNudgeTracker: Sendable {
    private var reminded: Set<AccessGrant> = []

    public init() {}

    public mutating func reminder(grants: [AccessGrant], at now: Date, isSuppressed: Bool = false) -> AccessGrant? {
        if reminded.contains(where: { $0.until <= now || !grants.contains($0) }) {
            reminded = reminded.filter { $0.until > now && grants.contains($0) }
        }
        guard !isSuppressed else { return nil }
        for grant in grants where grant.kind == .session && !reminded.contains(grant) {
            let remaining = grant.until.timeIntervalSince(now)
            // Do not claim two minutes remain after a long sleep or absence.
            guard remaining > 60, remaining <= 120 else { continue }
            reminded.insert(grant)
            return grant
        }
        return nil
    }
}
