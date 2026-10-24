import Foundation

/// A curated collection of templates added together from the Library.
public struct RulePack: Identifiable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var symbol: String
    public var templates: [RuleTemplate]

    public static let all: [RulePack] = [
        RulePack(
            id: "essentials", title: "Essentials",
            subtitle: "A breath before social and chat, and YouTube without Shorts. A gentle start.",
            symbol: "leaf",
            templates: [.mindfulSocial, .chatApps, .minimalYouTube]),
        RulePack(
            id: "deep-work", title: "Deep Work",
            subtitle: "Quiet mornings on weekdays, mail in batches, and a Focus blocklist ready to go.",
            symbol: "brain.head.profile",
            templates: [.deepWork, .emailBatches, .focusBlocklist]),
        RulePack(
            id: "evenings", title: "Evenings and Mornings",
            subtitle: "Screens wind down at night and feeds wait until the morning has started.",
            symbol: "moon.stars",
            templates: [.windDown, .slowMornings]),
        RulePack(
            id: "minimal-social", title: "Minimal Social",
            subtitle: "Keep messages and search; lose feeds, Reels and Shorts.",
            symbol: "bubble.left",
            templates: [.minimalSocial, .minimalYouTube]),
        RulePack(
            id: "play", title: "Games and Streaming",
            subtitle: "Games wait for the weekend; video and streaming share a daily budget.",
            symbol: "gamecontroller",
            templates: [.gamesOnWeekends, .distractingApps]),
        RulePack(
            id: "spending-news", title: "Spending and News",
            subtitle: "A pause before buying, and the news a few times a day instead of all day.",
            symbol: "bag",
            templates: [.mindfulShopping, .newsDiet]),
        RulePack(
            id: "safety", title: "Safety",
            subtitle: "Gambling and explicit pages, recognised by what they say rather than a list of sites.",
            symbol: "shield.lefthalf.filled",
            templates: [.gambling, .adult]),
    ]
}

extension RuleTemplate {
    public static let focusBlocklist = RuleTemplate(
        id: "focus-blocklist",
        title: "Focus blocklist",
        subtitle: "Social, entertainment, shopping and games, blocked only while a Focus session runs. Music keeps playing.",
        symbol: "moon"
    ) {
        Rule(
            name: "Focus blocklist", symbol: "moon",
            targets: [.category(.social), .category(.entertainment), .category(.shopping), .category(.games)],
            // Music in the background is part of focusing, not a distraction from it.
            exceptions: [
                .app(bundleID: "com.apple.Music", name: "Music"), .app(bundleID: "com.spotify.client", name: "Spotify"),
            ],
            schedule: .duringFocus, response: .track)
    }

    public static let emailBatches = RuleTemplate(
        id: "email-batches",
        title: "Mail in batches",
        subtitle: "Mail and webmail open six times a day, after a short pause.",
        symbol: "envelope"
    ) {
        Rule(
            name: "Mail in batches", symbol: "envelope",
            targets: [
                .app(bundleID: "com.apple.mail", name: "Mail"),
                .app(bundleID: "com.readdle.smartemail-Mac", name: "Spark"),
                .app(bundleID: "com.microsoft.Outlook", name: "Outlook"),
                .website(domain: "mail.google.com"), .website(domain: "outlook.live.com"),
                .website(domain: "outlook.office.com"),
            ],
            response: .pause(PauseSettings(waitSeconds: 5, escalationSeconds: 0, sessionMinutes: [10, 20])),
            limits: UsageLimits(dailyOpens: 6),
            message: "Batch it: read, reply, close.")
    }

    public static let windDown = RuleTemplate(
        id: "wind-down",
        title: "Wind down",
        subtitle: "From 22:00 to 07:00, social, video and games are blocked. You can still hold for a minute.",
        symbol: "moon.zzz"
    ) {
        Rule(
            name: "Wind down", symbol: "moon.zzz",
            targets: [.category(.social), .category(.entertainment), .category(.games)],
            exceptions: [.app(bundleID: "com.apple.Music", name: "Music"), .app(bundleID: "com.spotify.client", name: "Spotify")],
            schedule: .windows([
                ScheduleWindow(weekdays: ScheduleWindow.everyDay, startMinute: 22 * 60, endMinute: 7 * 60)
            ]),
            response: .block(BlockSettings(allowsOverride: true, closesAutomatically: false)),
            message: "It\u{2019}s late. This will still be here tomorrow.")
    }

    public static let slowMornings = RuleTemplate(
        id: "slow-mornings",
        title: "Slow mornings",
        subtitle: "No feeds or news before 09:00. Start the day with your own thoughts.",
        symbol: "sunrise"
    ) {
        Rule(
            name: "Slow mornings", symbol: "sunrise",
            targets: [.category(.social), .category(.reading), .category(.entertainment)],
            schedule: .windows([
                ScheduleWindow(weekdays: ScheduleWindow.everyDay, startMinute: 0, endMinute: 9 * 60)
            ]),
            response: .block(BlockSettings(allowsOverride: true, closesAutomatically: false)))
    }

    public static let mindfulShopping = RuleTemplate(
        id: "mindful-shopping",
        title: "Sleep on it",
        subtitle: "Shopping sites and apps open after a 30 second pause and a question.",
        symbol: "bag"
    ) {
        Rule(
            name: "Sleep on it", symbol: "bag",
            targets: [.category(.shopping)],
            response: .pause(
                PauseSettings(waitSeconds: 30, escalationSeconds: 0, sessionMinutes: [5, 15], asksIntention: true)),
            message: "Do you need it, or do you want the feeling of buying it?")
    }

    public static let newsDiet = RuleTemplate(
        id: "news-diet",
        title: "News diet",
        subtitle: "News sites open three times a day, for half an hour in total.",
        symbol: "newspaper"
    ) {
        Rule(
            name: "News diet", symbol: "newspaper",
            targets: [
                .website(domain: "nytimes.com"), .website(domain: "theguardian.com"), .website(domain: "bbc.com"),
                .website(domain: "bbc.co.uk"), .website(domain: "cnn.com"), .website(domain: "washingtonpost.com"),
                .website(domain: "apnews.com"), .website(domain: "reuters.com"), .website(domain: "news.google.com"),
                .website(domain: "foxnews.com"), .website(domain: "news.ycombinator.com"),
                .app(bundleID: "com.apple.news", name: "News"),
            ],
            response: .track,
            limits: UsageLimits(dailyMinutes: 30, dailyOpens: 3))
    }
}

extension RuleTemplate {
    /// Display names for apps the templates refer to, for when an app is not installed.
    public static func knownAppName(bundleID: String) -> String? {
        let targets = all.flatMap { template -> [Target] in
            let rule = template.make()
            return rule.targets + rule.exceptions
        }
        for case .app(let id, let name) in targets where id == bundleID { return name }
        return nil
    }
}
