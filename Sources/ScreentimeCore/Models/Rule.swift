import Foundation

/// What to watch, when, and how to respond when it is on screen.
public struct Rule: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// SF Symbol name shown in lists and on the shield card.
    public var symbol: String
    public var isEnabled: Bool
    public var targets: [Target]
    /// Matches here are never handled by this rule, even when a target matches.
    public var exceptions: [Target]
    public var schedule: RuleSchedule
    public var response: Response
    public var limits: UsageLimits
    /// Your own words on this rule's shield, such as "Is this important?".
    public var message: String?

    public init(
        id: UUID = UUID(),
        name: String,
        symbol: String = "hand.raised",
        isEnabled: Bool = true,
        targets: [Target] = [],
        exceptions: [Target] = [],
        schedule: RuleSchedule = .always,
        response: Response = .pause(PauseSettings()),
        limits: UsageLimits = UsageLimits(),
        message: String? = nil
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.isEnabled = isEnabled
        self.targets = targets
        self.exceptions = exceptions
        self.schedule = schedule
        self.response = response
        self.limits = limits
        self.message = message
    }

    /// Whether any target needs page text rather than only the address and title.
    public var needsPageText: Bool {
        targets.contains(where: \.needsPageText) || exceptions.contains(where: \.needsPageText)
    }
}

public enum Target: Codable, Hashable, Sendable, Identifiable {
    case app(bundleID: String, name: String)
    /// A host; matches the host and all subdomains. `www.` is ignored.
    case website(domain: String)
    /// `host/path` glob, for example `youtube.com/shorts/*`. A pattern that
    /// ends in `/` matches that exact path only.
    case urlPattern(String)
    /// Deep content inspection of the focused page or window.
    case content(ContentRule)
    case category(UsageCategory)

    public var id: String {
        switch self {
        case .app(let bundleID, _): "app:\(bundleID)"
        case .website(let domain): "site:\(domain)"
        case .urlPattern(let pattern): "url:\(pattern)"
        case .content(let rule):
            "content:\(rule.phrases.joined(separator: "|")):\(rule.minimumMatches):\(rule.scope.rawValue):\(rule.apps.joined(separator: ","))"
        case .category(let category): "category:\(category.rawValue)"
        }
    }

    public var needsPageText: Bool {
        if case .content(let rule) = self { return rule.scope == .pageText }
        return false
    }

    public var displayName: String {
        switch self {
        case .app(_, let name): name
        case .website(let domain): domain
        case .urlPattern(let pattern): pattern
        case .content(let rule): rule.summary
        case .category(let category): category.title
        }
    }

    public var kindName: String {
        switch self {
        case .app: "App"
        case .website: "Website"
        case .urlPattern: "Page"
        case .content: "Content"
        case .category: "Category"
        }
    }

    public var symbol: String {
        switch self {
        case .app: "app"
        case .website: "globe"
        case .urlPattern: "link"
        case .content: "text.magnifyingglass"
        case .category(let category): category.symbol
        }
    }
}

public enum ContentScope: String, Codable, Sendable, CaseIterable {
    /// Page title, window title and address. Cheap and immediate.
    case titleAndAddress
    /// Everything above plus the visible text of the page or window.
    case pageText
}

/// Phrases searched in the focused page or app window. Matching is case- and
/// diacritic-insensitive and respects word boundaries.
public struct ContentRule: Codable, Hashable, Sendable {
    public var phrases: [String]
    /// Total occurrences, across all phrases, needed to match.
    public var minimumMatches: Int
    public var scope: ContentScope
    /// Only inside these apps (bundle IDs). Empty means every app and browser.
    public var apps: [String]

    public init(
        phrases: [String], minimumMatches: Int = 1, scope: ContentScope = .pageText, apps: [String] = []
    ) {
        self.phrases = phrases
        self.minimumMatches = max(1, minimumMatches)
        self.scope = scope
        self.apps = apps
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phrases = try container.decode([String].self, forKey: .phrases)
        minimumMatches = try container.decode(Int.self, forKey: .minimumMatches)
        scope = try container.decode(ContentScope.self, forKey: .scope)
        apps = try container.decodeIfPresent([String].self, forKey: .apps) ?? []
    }

    public var summary: String {
        let shown = phrases.prefix(3).map { "\u{201C}\($0)\u{201D}" }.joined(separator: ", ")
        let more = phrases.count > 3 ? " +\(phrases.count - 3)" : ""
        return shown + more
    }
}

public enum RuleSchedule: Codable, Hashable, Sendable {
    case always
    case windows([ScheduleWindow])
    /// Only while a Focus session that includes this rule runs.
    case duringFocus
}

/// A weekly window. `endMinute <= startMinute` spans midnight; the window
/// belongs to the weekday on which it starts.
public struct ScheduleWindow: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// Calendar weekdays, 1 = Sunday ... 7 = Saturday.
    public var weekdays: Set<Int>
    public var startMinute: Int
    public var endMinute: Int

    public init(id: UUID = UUID(), weekdays: Set<Int>, startMinute: Int, endMinute: Int) {
        self.id = id
        self.weekdays = weekdays
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    public static let workdays: Set<Int> = [2, 3, 4, 5, 6]
    public static let everyDay: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
}

public enum Response: Codable, Hashable, Sendable {
    /// Count time and opens; never intervene unless a limit is exceeded.
    case track
    case pause(PauseSettings)
    case block(BlockSettings)

    public var title: String {
        switch self {
        case .track: "Track"
        case .pause: "Pause"
        case .block: "Block"
        }
    }
}

public struct PauseSettings: Codable, Hashable, Sendable {
    /// Wait before the first open of the day.
    public var waitSeconds: Int
    /// Added to the wait for every open already used today.
    public var escalationSeconds: Int
    /// Session lengths offered once the wait is over.
    public var sessionMinutes: [Int]
    /// Ask "What are you here for?" on the pause card.
    public var asksIntention: Bool

    public static let maximumWaitSeconds = 120

    public init(
        waitSeconds: Int = 10, escalationSeconds: Int = 5, sessionMinutes: [Int] = [2, 5, 15],
        asksIntention: Bool = true
    ) {
        self.waitSeconds = waitSeconds
        self.escalationSeconds = escalationSeconds
        self.sessionMinutes = sessionMinutes
        self.asksIntention = asksIntention
    }

    public func wait(afterOpens opens: Int) -> Int {
        min(Self.maximumWaitSeconds, waitSeconds + escalationSeconds * max(0, opens))
    }
}

public struct BlockSettings: Codable, Hashable, Sendable {
    /// Offer a press-and-hold one-minute override on the shield.
    public var allowsOverride: Bool
    /// Close the tab (browsers) or hide the app after showing the shield.
    public var closesAutomatically: Bool

    public init(allowsOverride: Bool = true, closesAutomatically: Bool = false) {
        self.allowsOverride = allowsOverride
        self.closesAutomatically = closesAutomatically
    }
}

/// Daily allowances. Exceeding any escalates the rule to Block for the rest of the day.
public struct UsageLimits: Codable, Hashable, Sendable {
    public var dailyMinutes: Int?
    public var dailyOpens: Int?

    public init(dailyMinutes: Int? = nil, dailyOpens: Int? = nil) {
        self.dailyMinutes = dailyMinutes
        self.dailyOpens = dailyOpens
    }

    public var isEmpty: Bool { dailyMinutes == nil && dailyOpens == nil }
}

/// A timed session that escalates a set of rules to Block.
public struct FocusSession: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var start: Date
    public var end: Date
    public var ruleIDs: [UUID]
    /// Locked sessions cannot be ended early and suppress overrides.
    public var isLocked: Bool

    public init(
        id: UUID = UUID(), title: String, start: Date, end: Date, ruleIDs: [UUID], isLocked: Bool
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.ruleIDs = ruleIDs
        self.isLocked = isLocked
    }

    public func isActive(at date: Date) -> Bool { date >= start && date < end }

    public func progress(at date: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 1 }
        return min(1, max(0, date.timeIntervalSince(start) / total))
    }
}

/// Temporary permission for one rule, from a finished pause or an override.
public struct AccessGrant: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case session
        case override
    }

    public var ruleID: UUID
    public var until: Date
    public var kind: Kind

    public init(ruleID: UUID, until: Date, kind: Kind) {
        self.ruleID = ruleID
        self.until = until
        self.kind = kind
    }
}
