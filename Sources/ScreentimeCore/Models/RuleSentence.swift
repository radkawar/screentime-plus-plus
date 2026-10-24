import Foundation

/// Shared wording for the editable sentence and compact rule summaries.
public struct RuleSentence: Sendable, Equatable {
    public let subject: String
    public let exceptions: String?
    public let schedule: String
    public let response: String
    public let limits: String?

    public init(rule: Rule) {
        subject = rule.targets.isEmpty ? "an app or site" : Self.list(Self.phrases(rule.targets), conjunction: "or")
        exceptions = rule.exceptions.isEmpty ? nil : "except " + Self.list(Self.phrases(rule.exceptions), conjunction: "or")
        schedule = Self.schedule(rule.schedule)
        switch rule.response {
        case .track:
            response = "track your time"
        case .pause(let settings):
            response = "pause \(settings.waitSeconds)s"
                + (settings.escalationSeconds > 0 ? ", \(settings.escalationSeconds)s longer each open" : " each open")
        case .block(let settings):
            response = "block access" + (settings.allowsOverride ? ", with a one-minute override" : ", without overrides")
                + (settings.closesAutomatically ? ", and close the tab or app" : "")
        }
        var allowances: [String] = []
        if let minutes = rule.limits.dailyMinutes { allowances.append("\(minutes) min") }
        if let opens = rule.limits.dailyOpens { allowances.append("\(opens) open\(opens == 1 ? "" : "s")") }
        limits = allowances.isEmpty ? nil : "stop after " + Self.list(allowances, conjunction: "or") + " a day"
    }

    public var text: String {
        "When you open \(subject)" + (exceptions.map { ", \($0)," } ?? "")
            + " \(schedule), \(response)" + (limits.map { " and \($0)" } ?? "") + "."
    }

    /// Categories share one "… apps and sites" phrase: "social, video or games apps and sites".
    private static func phrases(_ targets: [Target]) -> [String] {
        let categories = targets.compactMap { target -> String? in
            if case .category(let category) = target { return category.title.lowercased() }
            return nil
        }
        var result: [String] = []
        var placedCategories = false
        for target in targets {
            if case .category = target {
                guard !placedCategories else { continue }
                placedCategories = true
                result.append(list(categories, conjunction: "or") + " apps and sites")
            } else {
                result.append(self.target(target))
            }
        }
        return result
    }

    private static func target(_ target: Target) -> String {
        switch target {
        case .app(_, let name): return name
        case .website(let domain): return domain
        case .urlPattern(let pattern): return "pages at \(pattern)"
        case .category(let category): return "\(category.title.lowercased()) apps and sites"
        case .content(let content):
            let phrases = list(content.phrases.map { "“\($0)”" }, conjunction: "or")
            let location = content.scope == .titleAndAddress ? " in the title or address" : ""
            let threshold = content.minimumMatches > 1 ? " at least \(content.minimumMatches) times in total" : ""
            let apps = content.apps.isEmpty
                ? "" : " inside " + list(content.apps.map { RuleTemplate.knownAppName(bundleID: $0) ?? $0 }, conjunction: "or")
            return "pages that mention \(phrases.isEmpty ? "your phrases" : phrases)\(location)\(threshold)\(apps)"
        }
    }

    private static func schedule(_ schedule: RuleSchedule) -> String {
        switch schedule {
        case .always: return "any time"
        case .duringFocus: return "during Focus"
        case .windows(let windows):
            guard !windows.isEmpty else { return "on no scheduled days" }
            return windows.map { window in
                let days: String
                if window.weekdays == ScheduleWindow.everyDay { days = "every day" }
                else if window.weekdays == ScheduleWindow.workdays { days = "on weekdays" }
                else if window.weekdays == [1, 7] { days = "on weekends" }
                else {
                    let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                    let selected = window.weekdays.sorted().filter { (1...7).contains($0) }.map { names[$0 - 1] }
                    days = selected.isEmpty ? "on no days" : "on " + list(selected, conjunction: "and")
                }
                let overnight = window.endMinute <= window.startMinute ? " the next day" : ""
                return "\(days) from \(clock(window.startMinute)) to \(clock(window.endMinute))\(overnight)"
            }.joined(separator: "; or ")
        }
    }

    private static func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    private static func list(_ values: [String], conjunction: String) -> String {
        guard values.count > 1 else { return values.first ?? "" }
        if values.count == 2 { return values.joined(separator: " \(conjunction) ") }
        return values.dropLast().joined(separator: ", ") + ", \(conjunction) " + values[values.count - 1]
    }
}
