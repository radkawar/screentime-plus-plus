import AppKit
import Foundation

/// Categorises any installed app from the `LSApplicationCategoryType` it
/// declares in its Info.plist, so a Games rule covers every game rather than
/// a fixed list. Cached per bundle ID; safe from any thread.
public enum DeclaredAppCategory {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: UsageCategory?] = [:]

    public static func category(bundleID: String) -> UsageCategory? {
        lock.lock()
        if let cached = cache[bundleID] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let resolved = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .flatMap { Bundle(url: $0)?.infoDictionary?["LSApplicationCategoryType"] as? String }
            .flatMap(category(declared:))
        lock.lock()
        cache[bundleID] = .some(resolved)
        lock.unlock()
        return resolved
    }

    public static func category(declared raw: String) -> UsageCategory? {
        let type = raw.lowercased().replacingOccurrences(of: "public.app-category.", with: "")
        if type == "games" || type.hasSuffix("-games") { return .games }
        switch type {
        case "social-networking": return .social
        case "entertainment", "video", "music", "sports": return .entertainment
        case "news", "books", "reference", "magazines", "weather": return .reading
        case "productivity", "developer-tools", "business", "utilities", "graphics-design", "education",
            "finance", "medical", "healthcare-fitness":
            return .productivity
        default: return nil
        }
    }
}
