import Foundation

/// An app, site or named surface selected from live activity or History.
public struct DraftSubject: Sendable, Hashable {
    public var bundleID: String
    public var appName: String
    public var domain: String?
    public var surface: String?
    public var url: URL?

    public init(bundleID: String, appName: String, domain: String? = nil, surface: String? = nil, url: URL? = nil) {
        self.bundleID = bundleID
        self.appName = appName
        self.domain = domain.map(DomainName.normalize)
        self.surface = surface
        self.url = url
    }

    public init(context: ForegroundContext) {
        self.init(bundleID: context.bundleID, appName: context.appName, domain: context.domain,
                  surface: context.surface, url: context.url)
    }

    public init(total: UsageTotal) {
        self.init(bundleID: total.bundleID, appName: total.title, domain: total.domain)
    }
}

public enum DraftKind: String, CaseIterable, Sendable {
    case pause, limit, block
}

public enum RuleDraft {
    public static func rule(for subject: DraftSubject, kind: DraftKind) -> Rule {
        let targets: [Target]
        let name: String
        if let domain = subject.domain, !domain.isEmpty {
            let siteName = siteNames[domain] ?? domain
            if let surface = subject.surface {
                let patterns = SurfaceCatalog.surfaces.filter {
                    DomainName.host(domain, isWithin: $0.domain) && $0.name == surface
                }
                targets = patterns.isEmpty ? [.website(domain: domain)] : patterns.map { .urlPattern($0.pattern.raw) }
                name = patterns.isEmpty ? siteName : "\(siteName) \(surface)"
            } else {
                targets = [.website(domain: domain)]
                name = siteName
            }
        } else {
            targets = [.app(bundleID: subject.bundleID, name: subject.appName)]
            name = subject.appName
        }
        switch kind {
        case .pause:
            return Rule(name: name, targets: targets, response: .pause(PauseSettings()))
        case .limit:
            return Rule(name: name, symbol: "hourglass", targets: targets, response: .track,
                        limits: UsageLimits(dailyMinutes: 30))
        case .block:
            return Rule(name: name, targets: targets, response: .block(BlockSettings(allowsOverride: true)))
        }
    }

    private static let siteNames = [
        "youtube.com": "YouTube", "reddit.com": "Reddit", "x.com": "X", "twitter.com": "X",
        "instagram.com": "Instagram", "facebook.com": "Facebook", "linkedin.com": "LinkedIn",
        "tiktok.com": "TikTok", "netflix.com": "Netflix", "twitch.tv": "Twitch",
    ]
}
