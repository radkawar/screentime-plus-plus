import Foundation

public struct FocusProfile: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var minutes: Int
    public var isLocked: Bool
    public var categories: [UsageCategory]
    public var targets: [Target]
    public var ruleIDs: [UUID]
    public var windows: [ScheduleWindow]
    public var calendarTitleContains: String?
    /// Consumed occurrences prevent ended sessions restarting within their windows.
    public var consumedOccurrences: [String: Date]?

    public init(id: UUID = UUID(), name: String, minutes: Int = 50, isLocked: Bool = false,
                categories: [UsageCategory] = [.social, .entertainment], targets: [Target] = [],
                ruleIDs: [UUID] = [], windows: [ScheduleWindow] = [], calendarTitleContains: String? = nil) {
        self.id = id
        self.name = name
        self.minutes = minutes
        self.isLocked = isLocked
        self.categories = categories
        self.targets = targets
        self.ruleIDs = ruleIDs
        self.windows = windows
        self.calendarTitleContains = calendarTitleContains
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "Focus"
        minutes = try values.decodeIfPresent(Int.self, forKey: .minutes) ?? 50
        isLocked = try values.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        categories = try values.decodeIfPresent([UsageCategory].self, forKey: .categories) ?? []
        targets = try values.decodeIfPresent([Target].self, forKey: .targets) ?? []
        ruleIDs = try values.decodeIfPresent([UUID].self, forKey: .ruleIDs) ?? []
        windows = try values.decodeIfPresent([ScheduleWindow].self, forKey: .windows) ?? []
        calendarTitleContains = try values.decodeIfPresent(String.self, forKey: .calendarTitleContains)
        consumedOccurrences = try values.decodeIfPresent([String: Date].self, forKey: .consumedOccurrences)
    }

    public var hasSelection: Bool { !categories.isEmpty || !targets.isEmpty || !ruleIDs.isEmpty }

    public func session(start: Date, end: Date? = nil, automationID: String? = nil) -> FocusSession {
        FocusSession(title: name, start: start,
                     end: end ?? start.addingTimeInterval(TimeInterval(max(1, minutes)) * 60),
                     ruleIDs: ruleIDs, isLocked: isLocked, categories: categories, targets: targets,
                     automationID: automationID)
    }
}

/// EventKit is kept outside Core; only matching occurrences enter the decision.
public struct FocusCalendarOccurrence: Sendable, Equatable {
    public var id: String
    public var profileID: UUID
    public var start: Date
    public var end: Date

    public init(id: String, profileID: UUID, start: Date, end: Date) {
        self.id = id
        self.profileID = profileID
        self.start = start
        self.end = end
    }
}

public enum FocusAutomationDecision: Equatable, Sendable {
    case none
    case start(profileID: UUID, occurrenceID: String, end: Date)
    case stop
    case updateEnd(Date)
}

public enum FocusAutomation {
    /// Saved profile order wins overlapping windows. Manual sessions always take priority.
    public static func decision(profiles: [FocusProfile], current: FocusSession?,
                                events: [FocusCalendarOccurrence] = [], now: Date,
                                calendar: Calendar = .current) -> FocusAutomationDecision {
        if let current, current.isActive(at: now),
           current.isLocked || current.automationID == nil { return .none }
        var candidates: [(FocusProfile, String, Date)] = []
        for profile in profiles where profile.hasSelection {
            for window in profile.windows {
                if let end = ScheduleEvaluator.currentWindowEnd(.windows([window]), at: now, calendar: calendar) {
                    let id = "weekly:\(profile.id):\(window.id):\(end.timeIntervalSince1970)"
                    candidates.append((profile, id, end))
                }
            }
            for event in events where event.profileID == profile.id && event.start <= now && now < event.end {
                candidates.append((profile, "calendar:\(profile.id):\(event.id):\(event.start.timeIntervalSince1970)", event.end))
            }
        }
        if let current, current.isActive(at: now) {
            guard let id = current.automationID else { return .none }
            guard let candidate = candidates.first(where: { $0.1 == id }) else { return .stop }
            return candidate.2 == current.end ? .none : .updateEnd(candidate.2)
        }
        for (profile, id, end) in candidates where profile.consumedOccurrences?[id] == nil {
            return .start(profileID: profile.id, occurrenceID: id, end: end)
        }
        return .none
    }
}
