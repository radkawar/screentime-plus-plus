import Foundation

public enum DomainName {
    /// Lowercased host without a trailing dot or leading `www.`.
    public static func normalize(_ raw: String) -> String {
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let url = URLComponents(string: host.contains("://") ? host : "https://\(host)"),
            let parsed = url.host, !parsed.isEmpty
        {
            host = parsed
        }
        while host.hasSuffix(".") { host.removeLast() }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// `host` equals `domain` or is a subdomain of it.
    public static func host(_ host: String, isWithin domain: String) -> Bool {
        let host = normalize(host)
        let domain = normalize(domain)
        guard !domain.isEmpty else { return false }
        return host == domain || host.hasSuffix("." + domain)
    }
}

/// `host/path` glob matching. `*` matches any run of characters. The host part
/// also matches subdomains. A pattern without a path, or ending in `*`, covers
/// everything below it; a pattern ending in `/` matches that path exactly.
/// The query string is considered only when the pattern contains `?`.
public struct URLPattern: Hashable, Sendable {
    public let raw: String
    private let hostPattern: String
    private let pathPattern: String?

    public init(_ raw: String) {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let scheme = trimmed.range(of: "://") {
            trimmed = String(trimmed[scheme.upperBound...])
        }
        self.raw = trimmed
        if let slash = trimmed.firstIndex(of: "/") {
            hostPattern = DomainName.normalize(String(trimmed[..<slash]))
            pathPattern = String(trimmed[slash...])
        } else {
            hostPattern = DomainName.normalize(trimmed)
            pathPattern = nil
        }
    }

    public func matches(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        guard Self.hostMatches(DomainName.normalize(host), hostPattern) else { return false }
        guard let pathPattern else { return true }
        var subject = url.path.isEmpty ? "/" : url.path.lowercased()
        if pathPattern.contains("?"), let query = url.query {
            subject += "?" + query.lowercased()
        }
        return Self.glob(pathPattern, matches: subject)
    }

    private static func hostMatches(_ host: String, _ pattern: String) -> Bool {
        if pattern.contains("*") {
            return glob(pattern, matches: host)
        }
        return host == pattern || host.hasSuffix("." + pattern)
    }

    /// Iterative glob with `*` only; linear in practice for short patterns.
    static func glob(_ pattern: String, matches subject: String) -> Bool {
        let p = Array(pattern.utf8)
        let s = Array(subject.utf8)
        var pi = 0
        var si = 0
        var star = -1
        var mark = 0
        while si < s.count {
            if pi < p.count, p[pi] != UInt8(ascii: "*"), p[pi] == s[si] {
                pi += 1
                si += 1
            } else if pi < p.count, p[pi] == UInt8(ascii: "*") {
                star = pi
                mark = si
                pi += 1
            } else if star >= 0 {
                pi = star + 1
                mark += 1
                si = mark
            } else {
                return false
            }
        }
        while pi < p.count, p[pi] == UInt8(ascii: "*") { pi += 1 }
        return pi == p.count
    }
}

/// Text prepared once per snapshot for repeated phrase searches.
public struct FoldedText: Sendable, Equatable {
    public let value: String

    public init(_ text: String) {
        value = Self.fold(text)
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Whole-word occurrences of `phrase`. Runs of whitespace in both the
    /// text and the phrase compare as a single space.
    public func occurrences(of phrase: String, limit: Int = 1_000) -> Int {
        let needle = Self.fold(phrase.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchRange = value.startIndex..<value.endIndex
        while count < limit,
            let found = value.range(of: needle, options: [.literal], range: searchRange)
        {
            if isBoundary(before: found.lowerBound), isBoundary(after: found.upperBound) {
                count += 1
            }
            searchRange = found.upperBound..<value.endIndex
        }
        return count
    }

    private func isBoundary(before index: String.Index) -> Bool {
        guard index > value.startIndex else { return true }
        return !Self.isWordCharacter(value[value.index(before: index)])
    }

    private func isBoundary(after index: String.Index) -> Bool {
        guard index < value.endIndex else { return true }
        return !Self.isWordCharacter(value[index])
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}

/// Named parts of large sites, so History can say "YouTube: Shorts 41m".
public enum SurfaceCatalog {
    public struct Surface: Sendable, Hashable {
        public var domain: String
        public var name: String
        public var pattern: URLPattern
    }

    public static let surfaces: [Surface] = [
        .init(domain: "youtube.com", name: "Shorts", pattern: URLPattern("youtube.com/shorts/*")),
        .init(domain: "youtube.com", name: "Watch", pattern: URLPattern("youtube.com/watch*")),
        .init(domain: "youtube.com", name: "Search", pattern: URLPattern("youtube.com/results*")),
        .init(domain: "youtube.com", name: "Home feed", pattern: URLPattern("youtube.com/")),
        .init(domain: "youtube.com", name: "Subscriptions", pattern: URLPattern("youtube.com/feed/*")),
        .init(domain: "reddit.com", name: "Front page", pattern: URLPattern("reddit.com/")),
        .init(domain: "reddit.com", name: "Popular", pattern: URLPattern("reddit.com/r/popular*")),
        .init(domain: "reddit.com", name: "All", pattern: URLPattern("reddit.com/r/all*")),
        .init(domain: "reddit.com", name: "Threads", pattern: URLPattern("reddit.com/r/*/comments/*")),
        .init(domain: "reddit.com", name: "Communities", pattern: URLPattern("reddit.com/r/*")),
        .init(domain: "x.com", name: "Timeline", pattern: URLPattern("x.com/home*")),
        .init(domain: "x.com", name: "Explore", pattern: URLPattern("x.com/explore*")),
        .init(domain: "x.com", name: "Messages", pattern: URLPattern("x.com/messages*")),
        .init(domain: "x.com", name: "Posts", pattern: URLPattern("x.com/*/status/*")),
        .init(domain: "instagram.com", name: "Reels", pattern: URLPattern("instagram.com/reels/*")),
        .init(domain: "instagram.com", name: "Reels", pattern: URLPattern("instagram.com/reel/*")),
        .init(domain: "instagram.com", name: "Explore", pattern: URLPattern("instagram.com/explore/*")),
        .init(domain: "instagram.com", name: "Messages", pattern: URLPattern("instagram.com/direct/*")),
        .init(domain: "instagram.com", name: "Feed", pattern: URLPattern("instagram.com/")),
        .init(domain: "facebook.com", name: "Feed", pattern: URLPattern("facebook.com/")),
        .init(domain: "facebook.com", name: "Reels", pattern: URLPattern("facebook.com/reel/*")),
        .init(domain: "facebook.com", name: "Watch", pattern: URLPattern("facebook.com/watch*")),
        .init(domain: "facebook.com", name: "Messages", pattern: URLPattern("facebook.com/messages/*")),
        .init(domain: "linkedin.com", name: "Feed", pattern: URLPattern("linkedin.com/feed*")),
        .init(domain: "linkedin.com", name: "Messages", pattern: URLPattern("linkedin.com/messaging*")),
        .init(domain: "tiktok.com", name: "For You", pattern: URLPattern("tiktok.com/")),
    ]

    public static func surface(for url: URL) -> String? {
        surfaces.first { $0.pattern.matches(url) }?.name
    }
}
