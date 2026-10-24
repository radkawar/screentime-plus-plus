import Foundation

/// Starting points offered when creating a rule. Each is an ordinary rule the
/// user can edit afterwards.
public struct RuleTemplate: Identifiable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var symbol: String
    public var make: @Sendable () -> Rule

    public static let all: [RuleTemplate] = [
        minimalYouTube, minimalSocial, mindfulSocial, deepWork, gambling, adult, blank,
    ]

    public static let minimalYouTube = RuleTemplate(
        id: "minimal-youtube",
        title: "YouTube without Shorts",
        subtitle: "Block Shorts and the home feed. Search, subscriptions and videos stay open.",
        symbol: "play.rectangle"
    ) {
        Rule(
            name: "YouTube without Shorts",
            symbol: "play.rectangle",
            targets: [.urlPattern("youtube.com/shorts/*"), .urlPattern("youtube.com/")],
            response: .block(BlockSettings(allowsOverride: false, closesAutomatically: false))
        )
    }

    public static let minimalSocial = RuleTemplate(
        id: "minimal-social",
        title: "Messages only",
        subtitle: "Feeds, Reels and Explore are blocked on Instagram, Facebook, X and LinkedIn. Messages stay open.",
        symbol: "bubble.left"
    ) {
        Rule(
            name: "Messages only",
            symbol: "bubble.left",
            targets: [
                .urlPattern("instagram.com/"), .urlPattern("instagram.com/reels/*"),
                .urlPattern("instagram.com/reel/*"), .urlPattern("instagram.com/explore/*"),
                .urlPattern("facebook.com/"), .urlPattern("facebook.com/reel/*"),
                .urlPattern("facebook.com/watch*"), .urlPattern("x.com/home*"),
                .urlPattern("x.com/explore*"), .urlPattern("linkedin.com/feed*"),
                .website(domain: "tiktok.com"),
            ],
            response: .block(BlockSettings(allowsOverride: true, closesAutomatically: false))
        )
    }

    public static let mindfulSocial = RuleTemplate(
        id: "mindful-social",
        title: "Pause before social",
        subtitle: "A short breath before social sites, a little longer each time, in sessions you choose.",
        symbol: "wind"
    ) {
        Rule(
            name: "Pause before social",
            symbol: "wind",
            targets: [.category(.social)],
            response: .pause(PauseSettings(waitSeconds: 10, escalationSeconds: 5)),
            limits: UsageLimits(dailyMinutes: 45, dailyOpens: 12)
        )
    }

    public static let deepWork = RuleTemplate(
        id: "deep-work",
        title: "Deep work hours",
        subtitle: "Weekdays 9:00 to 12:00, entertainment, social and shopping are blocked.",
        symbol: "brain.head.profile"
    ) {
        Rule(
            name: "Deep work",
            symbol: "brain.head.profile",
            targets: [.category(.entertainment), .category(.social), .category(.shopping)],
            schedule: .windows([
                ScheduleWindow(weekdays: ScheduleWindow.workdays, startMinute: 9 * 60, endMinute: 12 * 60)
            ]),
            response: .block(BlockSettings(allowsOverride: true, closesAutomatically: false))
        )
    }

    public static let gambling = RuleTemplate(
        id: "gambling",
        title: "Gambling",
        subtitle: "Blocks any page that talks about betting, whatever the site.",
        symbol: "suit.club"
    ) {
        Rule(
            name: "Gambling",
            symbol: "suit.club",
            targets: [
                .content(
                    ContentRule(
                        phrases: [
                            "sportsbook", "casino", "online casino", "free spins", "betting odds",
                            "place your bet", "parlay", "roulette", "blackjack", "slot machine",
                            "jackpot", "bookmaker", "wager",
                        ],
                        minimumMatches: 4,
                        scope: .pageText
                    ))
            ],
            response: .block(BlockSettings(allowsOverride: false, closesAutomatically: true))
        )
    }

    public static let adult = RuleTemplate(
        id: "adult",
        title: "Adult content",
        subtitle: "Blocks explicit pages anywhere, by reading the page rather than a list of sites.",
        symbol: "eye.slash"
    ) {
        Rule(
            name: "Adult content",
            symbol: "eye.slash",
            targets: [
                .content(
                    ContentRule(
                        phrases: [
                            "porn", "porno", "pornhub", "xxx", "nsfw", "nude", "nudes", "onlyfans",
                            "camgirl", "hentai", "milf", "explicit sex",
                        ],
                        minimumMatches: 3,
                        scope: .pageText
                    ))
            ],
            response: .block(BlockSettings(allowsOverride: false, closesAutomatically: true))
        )
    }

    public static let blank = RuleTemplate(
        id: "blank",
        title: "Start from scratch",
        subtitle: "Choose your own apps, sites, pages and phrases.",
        symbol: "plus"
    ) {
        Rule(name: "New rule", symbol: "hand.raised")
    }
}
