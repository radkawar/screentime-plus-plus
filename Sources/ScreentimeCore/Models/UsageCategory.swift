import Foundation

/// Broad grouping for reporting and for category shields.
public enum UsageCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case social
    case entertainment
    case productivity
    case communication
    case reading
    case games
    case shopping
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .social: "Social"
        case .entertainment: "Entertainment"
        case .productivity: "Productivity"
        case .communication: "Communication"
        case .reading: "Reading & News"
        case .games: "Games"
        case .shopping: "Shopping"
        case .other: "Other"
        }
    }

    public var symbol: String {
        switch self {
        case .social: "person.2"
        case .entertainment: "play.rectangle"
        case .productivity: "hammer"
        case .communication: "bubble.left.and.bubble.right"
        case .reading: "newspaper"
        case .games: "gamecontroller"
        case .shopping: "bag"
        case .other: "square.grid.2x2"
        }
    }
}

/// Built-in classification of well-known apps and sites. Lookups are exact on
/// bundle identifiers and suffix-aware on domains (`m.youtube.com` is
/// `youtube.com`).
public enum CategoryCatalog {
    public static func category(bundleID: String, domain: String?) -> UsageCategory {
        if let domain, let category = category(domain: domain) {
            return category
        }
        if BrowserCatalog.isBrowser(bundleID: bundleID) {
            return .other
        }
        return apps[bundleID] ?? .other
    }

    public static func category(domain: String) -> UsageCategory? {
        var candidate = DomainName.normalize(domain)
        while !candidate.isEmpty {
            if let category = domains[candidate] { return category }
            guard let dot = candidate.firstIndex(of: ".") else { break }
            candidate = String(candidate[candidate.index(after: dot)...])
        }
        return nil
    }

    /// Well-known domains per category, used by category shields.
    public static func domains(in category: UsageCategory) -> [String] {
        domains.filter { $0.value == category }.map(\.key).sorted()
    }

    public static func apps(in category: UsageCategory) -> [String] {
        apps.filter { $0.value == category }.map(\.key).sorted()
    }

    static let apps: [String: UsageCategory] = [
        "com.apple.Xcode": .productivity,
        "com.microsoft.VSCode": .productivity,
        "com.todesktop.230313mzl4w4u92": .productivity,  // Cursor
        "dev.zed.Zed": .productivity,
        "com.apple.Terminal": .productivity,
        "com.googlecode.iterm2": .productivity,
        "com.mitchellh.ghostty": .productivity,
        "dev.warp.Warp-Stable": .productivity,
        "com.apple.dt.Instruments": .productivity,
        "com.figma.Desktop": .productivity,
        "notion.id": .productivity,
        "md.obsidian": .productivity,
        "com.apple.Notes": .productivity,
        "com.apple.iWork.Pages": .productivity,
        "com.apple.iWork.Numbers": .productivity,
        "com.apple.iWork.Keynote": .productivity,
        "com.microsoft.Word": .productivity,
        "com.microsoft.Excel": .productivity,
        "com.microsoft.Powerpoint": .productivity,
        "com.linear": .productivity,
        "com.apple.finder": .productivity,
        "com.apple.mail": .communication,
        "com.apple.MobileSMS": .communication,
        "com.apple.FaceTime": .communication,
        "com.tinyspeck.slackmacgap": .communication,
        "com.hnc.Discord": .communication,
        "us.zoom.xos": .communication,
        "com.microsoft.teams2": .communication,
        "net.whatsapp.WhatsApp": .communication,
        "ru.keepcoder.Telegram": .communication,
        "org.whispersystems.signal-desktop": .communication,
        "com.readdle.smartemail-Mac": .communication,
        "com.apple.Music": .entertainment,
        "com.apple.TV": .entertainment,
        "com.spotify.client": .entertainment,
        "com.apple.podcasts": .entertainment,
        "com.netflix.Netflix": .entertainment,
        "tv.twitch.studio": .entertainment,
        "com.apple.news": .reading,
        "com.apple.iBooksX": .reading,
        "net.shinyfrog.bear": .productivity,
        "com.valvesoftware.steam": .games,
        "com.apple.Chess": .games,
        "com.epicgames.EpicGamesLauncher": .games,
        "com.apple.AppStore": .shopping,
    ]

    static let domains: [String: UsageCategory] = [
        // Social
        "x.com": .social, "twitter.com": .social, "facebook.com": .social,
        "instagram.com": .social, "threads.net": .social, "reddit.com": .social,
        "tiktok.com": .social, "linkedin.com": .social, "bsky.app": .social,
        "mastodon.social": .social, "pinterest.com": .social, "tumblr.com": .social,
        "snapchat.com": .social, "news.ycombinator.com": .social,
        // Entertainment
        "youtube.com": .entertainment, "youtu.be": .entertainment, "netflix.com": .entertainment,
        "twitch.tv": .entertainment, "primevideo.com": .entertainment, "disneyplus.com": .entertainment,
        "hulu.com": .entertainment, "max.com": .entertainment, "spotify.com": .entertainment,
        "soundcloud.com": .entertainment, "vimeo.com": .entertainment, "9gag.com": .entertainment,
        "imgur.com": .entertainment, "tv.apple.com": .entertainment,
        // Reading & news
        "nytimes.com": .reading, "theguardian.com": .reading, "bbc.com": .reading,
        "bbc.co.uk": .reading, "cnn.com": .reading, "washingtonpost.com": .reading,
        "theverge.com": .reading, "wikipedia.org": .reading, "medium.com": .reading,
        "substack.com": .reading, "economist.com": .reading, "ft.com": .reading,
        "bloomberg.com": .reading, "reuters.com": .reading, "apnews.com": .reading,
        "arstechnica.com": .reading, "wired.com": .reading, "news.google.com": .reading,
        // Productivity
        "github.com": .productivity, "gitlab.com": .productivity, "stackoverflow.com": .productivity,
        "developer.apple.com": .productivity, "docs.google.com": .productivity,
        "notion.so": .productivity, "figma.com": .productivity, "linear.app": .productivity,
        "atlassian.net": .productivity, "vercel.com": .productivity, "cloudflare.com": .productivity,
        "chatgpt.com": .productivity, "claude.ai": .productivity, "grok.com": .productivity,
        // Communication
        "mail.google.com": .communication, "outlook.live.com": .communication,
        "outlook.office.com": .communication, "slack.com": .communication,
        "discord.com": .communication, "web.whatsapp.com": .communication,
        "messenger.com": .communication, "web.telegram.org": .communication,
        "meet.google.com": .communication, "zoom.us": .communication,
        // Games
        "chess.com": .games, "lichess.org": .games, "roblox.com": .games,
        "steampowered.com": .games, "poki.com": .games, "crazygames.com": .games,
        // Shopping
        "amazon.com": .shopping, "amazon.co.uk": .shopping, "ebay.com": .shopping,
        "etsy.com": .shopping, "aliexpress.com": .shopping, "temu.com": .shopping,
        "shein.com": .shopping, "walmart.com": .shopping, "target.com": .shopping,
        "bestbuy.com": .shopping,
    ]
}
