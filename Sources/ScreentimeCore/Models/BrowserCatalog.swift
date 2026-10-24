import Foundation

/// Browsers whose focused window exposes an AXWebArea with the page address.
public enum BrowserCatalog {
    public static let bundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.canary",
        "com.google.Chrome.dev",
        "org.chromium.Chromium",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "company.thebrowser.Browser",  // Arc
        "company.thebrowser.dia",  // Dia
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "app.zen-browser.zen",
        "com.kagi.kagimacOS",  // Orion
        "ai.perplexity.comet",
    ]

    /// Chromium and Gecko only build their web accessibility tree after an
    /// assistive client asks for it.
    public static let needsManualAccessibility: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.canary",
        "com.google.Chrome.dev",
        "org.chromium.Chromium",
        "company.thebrowser.Browser",
        "company.thebrowser.dia",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "ai.perplexity.comet",
    ]

    public static func isBrowser(bundleID: String?) -> Bool {
        bundleID.map(bundleIDs.contains) ?? false
    }
}
