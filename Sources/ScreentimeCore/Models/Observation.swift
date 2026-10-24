import Foundation

/// What is in front of the user right now.
public struct ForegroundContext: Sendable, Equatable {
    public var bundleID: String
    public var appName: String
    public var pid: pid_t
    public var isBrowser: Bool
    /// HTTP(S) address of the focused tab, when one could be read.
    public var url: URL?
    public var windowTitle: String?
    public var pageTitle: String?

    public init(
        bundleID: String, appName: String, pid: pid_t, isBrowser: Bool, url: URL? = nil,
        windowTitle: String? = nil, pageTitle: String? = nil
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.pid = pid
        self.isBrowser = isBrowser
        self.url = url
        self.windowTitle = windowTitle
        self.pageTitle = pageTitle
    }

    public var domain: String? {
        url?.host.map(DomainName.normalize)
    }

    public var surface: String? {
        url.flatMap(SurfaceCatalog.surface(for:))
    }

    public var category: UsageCategory {
        CategoryCatalog.category(bundleID: bundleID, domain: domain)
    }

    /// The thing a grant or override applies to: the site in a browser, else the app.
    public var subject: String {
        domain ?? bundleID
    }

    /// Text for title-and-address content rules.
    public var headline: String {
        [pageTitle, windowTitle, url?.absoluteString].compactMap { $0 }.joined(separator: "\n")
    }
}

/// Text read from the focused page or window for deep inspection.
public struct PageContent: Sendable, Equatable {
    public var text: FoldedText
    public var characterCount: Int
    public var nodeCount: Int
    /// Traversal stopped at a node, time or size budget.
    public var isPartial: Bool
    public var capturedAt: Date
    /// Identity of what was read, so stale text is never applied to a new page.
    public var sourceKey: String

    public init(
        text: String, nodeCount: Int, isPartial: Bool, capturedAt: Date, sourceKey: String
    ) {
        self.text = FoldedText(text)
        self.characterCount = text.count
        self.nodeCount = nodeCount
        self.isPartial = isPartial
        self.capturedAt = capturedAt
        self.sourceKey = sourceKey
    }
}
