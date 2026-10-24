import AppKit
import SwiftUI

struct InstalledApp: Identifiable, Hashable, Sendable {
    var bundleID: String
    var name: String
    var url: URL
    var id: String { bundleID }
}

/// Installed applications for the rule editor's app picker.
enum AppCatalog {
    static func installed() async -> [InstalledApp] {
        await Task.detached(priority: .userInitiated) {
            let manager = FileManager.default
            let roots = [
                URL(fileURLWithPath: "/Applications"),
                URL(fileURLWithPath: "/System/Applications"),
                URL(fileURLWithPath: "/System/Applications/Utilities"),
                manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
            ]
            var found: [String: InstalledApp] = [:]
            for root in roots {
                guard
                    let entries = try? manager.contentsOfDirectory(
                        at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                else { continue }
                var bundles = entries.filter { $0.pathExtension == "app" }
                // One level of folders, e.g. /Applications/Utilities or vendor folders.
                for folder in entries where folder.pathExtension.isEmpty {
                    let nested = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
                    bundles += nested.filter { $0.pathExtension == "app" }
                }
                for url in bundles {
                    guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                        id != Bundle.main.bundleIdentifier
                    else { continue }
                    let name =
                        (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
                        ?? (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                        ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                        ?? url.deletingPathExtension().lastPathComponent
                    if found[id] == nil { found[id] = InstalledApp(bundleID: id, name: name, url: url) }
                }
            }
            return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }.value
    }
}

/// App icons by bundle identifier, cached for the process lifetime.
@MainActor
enum IconCache {
    private static var icons: [String: NSImage] = [:]

    static func icon(bundleID: String) -> NSImage? {
        if let cached = icons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleID] = icon
        return icon
    }
}
