import Foundation

/// Why a target matched; shown on the shield and in the inspector.
public enum MatchEvidence: Hashable, Sendable {
    case app(String)
    case website(String)
    case urlPattern(String)
    case phrases([PhraseCount], total: Int)
    case category(UsageCategory)

    public var summary: String {
        switch self {
        case .app(let name): name
        case .website(let domain): domain
        case .urlPattern(let pattern): pattern
        case .phrases(let counts, let total):
            counts.prefix(3).map { "\u{201C}\($0.phrase)\u{201D}" }.joined(separator: ", ")
                + " \u{00B7} \(total) mention\(total == 1 ? "" : "s")"
        case .category(let category): category.title
        }
    }
}

public struct PhraseCount: Hashable, Sendable {
    public var phrase: String
    public var count: Int
}

public struct RuleMatch: Hashable, Sendable {
    public var rule: Rule
    public var target: Target
    public var evidence: MatchEvidence
}

public enum BlockReason: Hashable, Sendable {
    case rule
    case focus(title: String, until: Date, locked: Bool)
    case minutesLimit(Int)
    case opensLimit(Int)
}

public struct PauseIntervention: Hashable, Sendable {
    public var match: RuleMatch
    public var waitSeconds: Int
    public var sessionMinutes: [Int]
    public var asksIntention: Bool
    /// Opens already used today, before this one.
    public var opensToday: Int
}

public struct BlockIntervention: Hashable, Sendable {
    public var match: RuleMatch
    public var reason: BlockReason
    public var allowsOverride: Bool
    public var closesAutomatically: Bool
    /// When the block lifts on its own, if known.
    public var until: Date?
}

public enum Intervention: Hashable, Sendable {
    case pause(PauseIntervention)
    case block(BlockIntervention)

    public var match: RuleMatch {
        switch self {
        case .pause(let pause): pause.match
        case .block(let block): block.match
        }
    }

    var rank: Int {
        switch self {
        case .pause: 1
        case .block(let block):
            if case .focus = block.reason { 3 } else { 2 }
        }
    }
}

/// Mutable per-day state the engine reads but never writes.
public struct RuleRuntime: Sendable, Equatable {
    public var usageSeconds: [UUID: TimeInterval]
    public var opens: [UUID: Int]
    public var grants: [AccessGrant]
    public var focus: FocusSession?

    public init(
        usageSeconds: [UUID: TimeInterval] = [:], opens: [UUID: Int] = [:],
        grants: [AccessGrant] = [], focus: FocusSession? = nil
    ) {
        self.usageSeconds = usageSeconds
        self.opens = opens
        self.grants = grants
        self.focus = focus
    }

    public func grant(for ruleID: UUID, at date: Date) -> AccessGrant? {
        grants.filter { $0.ruleID == ruleID && $0.until > date }.max { $0.until < $1.until }
    }
}

public struct Evaluation: Sendable, Equatable {
    /// Every enabled rule whose targets match, scheduled or not. Used for usage accounting.
    public var matches: [RuleMatch]
    /// The strongest intervention due now, if any.
    public var intervention: Intervention?

    public static let none = Evaluation(matches: [], intervention: nil)
}

public enum PolicyEngine {
    public static func evaluate(
        context: ForegroundContext,
        content: PageContent?,
        rules: [Rule],
        runtime: RuleRuntime,
        now: Date,
        calendar: Calendar = .current
    ) -> Evaluation {
        let headline = FoldedText(context.headline)
        var matches = rules.compactMap { rule -> RuleMatch? in
            guard rule.isEnabled else { return nil }
            return match(rule: rule, context: context, headline: headline, content: content)
        }
        let focus = runtime.focus.flatMap { $0.isActive(at: now) ? $0 : nil }
        if let focus {
            var matched: (Target, MatchEvidence)?
            if let categories = focus.categories, !categories.isEmpty {
                let category = context.category
                if categories.contains(category) { matched = (.category(category), .category(category)) }
            }
            if matched == nil, let targets = focus.targets {
                for target in targets {
                    if let evidence = evidence(for: target, context: context, headline: headline, content: content) {
                        matched = (target, evidence)
                        break
                    }
                }
            }
            if let (target, evidence) = matched {
                let rule = Rule(id: focus.id, name: focus.title, symbol: "moon.fill", targets: [target],
                                response: .block(BlockSettings(allowsOverride: !focus.isLocked)))
                matches.append(RuleMatch(rule: rule, target: target, evidence: evidence))
            }
        }

        var best: Intervention?
        for match in matches {
            guard
                let candidate = intervention(
                    for: match, runtime: runtime, focus: focus, now: now, calendar: calendar)
            else { continue }
            if best == nil || candidate.rank > best!.rank {
                best = candidate
            }
        }
        return Evaluation(matches: matches, intervention: best)
    }

    static func intervention(
        for match: RuleMatch,
        runtime: RuleRuntime,
        focus: FocusSession?,
        now: Date,
        calendar: Calendar
    ) -> Intervention? {
        let rule = match.rule
        let inFocus = focus.map { $0.id == rule.id || $0.ruleIDs.contains(rule.id) } ?? false
        let scheduled = inFocus || ScheduleEvaluator.isActive(rule.schedule, at: now, calendar: calendar)
        guard scheduled else { return nil }

        let grant = runtime.grant(for: rule.id, at: now)
        let lockedFocus = inFocus && (focus?.isLocked ?? false)
        if let grant, grant.kind == .override, !lockedFocus {
            return nil
        }

        if inFocus, let focus {
            return .block(
                BlockIntervention(
                    match: match,
                    reason: .focus(title: focus.title, until: focus.end, locked: focus.isLocked),
                    allowsOverride: !focus.isLocked,
                    closesAutomatically: false,
                    until: focus.end
                ))
        }

        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        let blockSettings: BlockSettings = {
            if case .block(let settings) = rule.response { return settings }
            return BlockSettings(allowsOverride: true, closesAutomatically: false)
        }()
        if let minutes = rule.limits.dailyMinutes,
            runtime.usageSeconds[rule.id, default: 0] >= TimeInterval(minutes * 60)
        {
            return .block(
                BlockIntervention(
                    match: match, reason: .minutesLimit(minutes),
                    allowsOverride: blockSettings.allowsOverride,
                    closesAutomatically: blockSettings.closesAutomatically, until: endOfDay))
        }
        let opens = runtime.opens[rule.id, default: 0]
        if let limit = rule.limits.dailyOpens, opens >= limit, grant == nil {
            return .block(
                BlockIntervention(
                    match: match, reason: .opensLimit(limit),
                    allowsOverride: blockSettings.allowsOverride,
                    closesAutomatically: blockSettings.closesAutomatically, until: endOfDay))
        }

        switch rule.response {
        case .track:
            return nil
        case .pause(let settings):
            if grant != nil { return nil }
            return .pause(
                PauseIntervention(
                    match: match,
                    waitSeconds: settings.wait(afterOpens: opens),
                    sessionMinutes: settings.sessionMinutes,
                    asksIntention: settings.asksIntention,
                    opensToday: opens
                ))
        case .block(let settings):
            return .block(
                BlockIntervention(
                    match: match, reason: .rule, allowsOverride: settings.allowsOverride,
                    closesAutomatically: settings.closesAutomatically,
                    until: ScheduleEvaluator.currentWindowEnd(rule.schedule, at: now, calendar: calendar)
                ))
        }
    }

    public static func match(
        rule: Rule, context: ForegroundContext, headline: FoldedText, content: PageContent?
    ) -> RuleMatch? {
        for exception in rule.exceptions
        where evidence(for: exception, context: context, headline: headline, content: content) != nil {
            return nil
        }
        for target in rule.targets {
            if let evidence = evidence(for: target, context: context, headline: headline, content: content) {
                return RuleMatch(rule: rule, target: target, evidence: evidence)
            }
        }
        return nil
    }

    public static func evidence(
        for target: Target, context: ForegroundContext, headline: FoldedText, content: PageContent?
    ) -> MatchEvidence? {
        switch target {
        case .app(let bundleID, let name):
            return context.bundleID == bundleID ? .app(name) : nil
        case .website(let domain):
            guard let host = context.domain, DomainName.host(host, isWithin: domain) else { return nil }
            return .website(DomainName.normalize(domain))
        case .urlPattern(let raw):
            guard let url = context.url else { return nil }
            let pattern = URLPattern(raw)
            return pattern.matches(url) ? .urlPattern(pattern.raw) : nil
        case .category(let category):
            return context.category == category ? .category(category) : nil
        case .content(let rule):
            guard rule.apps.isEmpty || rule.apps.contains(context.bundleID) else { return nil }
            var counts: [PhraseCount] = []
            var total = 0
            for phrase in rule.phrases {
                var count = headline.occurrences(of: phrase)
                if rule.scope == .pageText, let content {
                    count += content.text.occurrences(of: phrase)
                }
                if count > 0 {
                    counts.append(PhraseCount(phrase: phrase, count: count))
                    total += count
                }
            }
            guard total >= rule.minimumMatches else { return nil }
            return .phrases(counts.sorted { $0.count > $1.count }, total: total)
        }
    }
}
