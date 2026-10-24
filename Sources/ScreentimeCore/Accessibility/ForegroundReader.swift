import AppKit
import ApplicationServices
import Foundation

/// A read of the focused window of one application. Holds live AX elements,
/// so it must stay on the queue that produced it.
public struct ForegroundReading: @unchecked Sendable {
    public var context: ForegroundContext
    /// Focused window frame in AX global coordinates (top-left origin, y down).
    public var windowFrame: CGRect?
    /// Frame of the page area inside a browser window, same coordinates.
    public var contentFrame: CGRect?
    /// False when AX was unavailable or timed out: the caller should keep its
    /// previous decision rather than treat the page as allowed.
    public var isComplete: Bool
    var window: AXUIElement?
    var webArea: AXUIElement?
}

/// Reads the active app, focused window, page address and page text through
/// Accessibility. Not thread-safe; confine to one serial queue.
public final class ForegroundReader: @unchecked Sendable {
    public var contentNodeBudget = 4_000
    public var contentCharacterBudget = 80_000
    public var contentTimeBudget: Duration = .milliseconds(350)

    private var accessibilityEnabledPIDs: Set<pid_t> = []
    private let ownPID = getpid()

    public init() {}

    public func read(_ app: NSRunningApplication) -> ForegroundReading {
        let bundleID = app.bundleIdentifier ?? "pid.\(app.processIdentifier)"
        let isBrowser = BrowserCatalog.isBrowser(bundleID: bundleID)
        var context = ForegroundContext(
            bundleID: bundleID,
            appName: app.localizedName ?? bundleID,
            pid: app.processIdentifier,
            isBrowser: isBrowser
        )
        var reading = ForegroundReading(context: context, windowFrame: nil, contentFrame: nil, isComplete: false)
        guard AccessibilityPermission.isTrusted, app.processIdentifier != ownPID, !app.isTerminated else {
            return reading
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.15)
        enableWebAccessibilityIfNeeded(appElement, pid: app.processIdentifier, bundleID: bundleID)

        let ax = AXRead(budget: .milliseconds(450))
        do {
            guard let window = try ax.element(appElement, kAXFocusedWindowAttribute as String) else {
                // No focused window (for example only a menu bar app): a complete, empty read.
                reading.isComplete = true
                return reading
            }
            reading.window = window
            context.windowTitle = try ax.string(window, kAXTitleAttribute as String)
            reading.windowFrame = try ax.frame(window)
            if isBrowser {
                let document = try ax.string(window, kAXDocumentAttribute as String)
                let web = try findWebArea(in: window, ax: ax)
                reading.webArea = web?.element
                if let element = web?.element {
                    reading.contentFrame = try ax.frame(element)
                }
                let address = web?.url ?? document
                context.url = address.flatMap(Self.website)
                if let title = web?.title, !title.isEmpty {
                    context.pageTitle = title
                }
                // Focus can move while AX answers; never attach one window's
                // address to another.
                guard let current = try ax.element(appElement, kAXFocusedWindowAttribute as String),
                    CFEqual(current, window)
                else {
                    reading.context = context
                    return reading
                }
            }
            reading.context = context
            reading.isComplete = true
        } catch {
            reading.context = context
        }
        return reading
    }

    /// Frame of the focused window only, for keeping a shield aligned.
    public func focusedWindowFrame(pid: pid_t) -> CGRect? {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.08)
        let ax = AXRead(budget: .milliseconds(120))
        guard let window = try? ax.element(appElement, kAXFocusedWindowAttribute as String) else { return nil }
        return try? ax.frame(window)
    }

    /// Visible text of the page (browsers) or window (other apps). Text is
    /// returned to the caller for matching and never persisted.
    public func inspectContent(_ reading: ForegroundReading, now: Date = Date()) -> PageContent? {
        guard let root = reading.webArea ?? reading.window else { return nil }
        let ax = AXRead(budget: contentTimeBudget)
        var collector = TextCollector(characterBudget: contentCharacterBudget)
        var nodes = 0
        var partial = false
        var stack: [(AXUIElement, Int)] = [(root, 0)]
        let names = [
            kAXRoleAttribute as String, kAXValueAttribute as String, kAXTitleAttribute as String,
            kAXDescriptionAttribute as String, kAXChildrenAttribute as String,
        ]
        while let (element, depth) = stack.popLast() {
            guard nodes < contentNodeBudget, collector.hasRoom else {
                partial = true
                break
            }
            guard let values = try? ax.multiple(element, names) else {
                partial = true
                if !ax.hasTimeLeft { break }
                continue
            }
            nodes += 1
            let role = values[0].flatMap(AXRead.string(from:)) ?? ""
            if Self.skippedRoles.contains(role) { continue }
            switch role {
            case "AXStaticText", "AXTextField", "AXTextArea", "AXSearchField", "AXComboBox":
                collector.append(values[1].flatMap(AXRead.string(from:)))
            case "AXHeading", "AXImage", "AXCell":
                collector.append(values[2].flatMap(AXRead.string(from:)))
                collector.append(values[3].flatMap(AXRead.string(from:)))
            case "AXWindow", "AXWebArea":
                collector.append(values[2].flatMap(AXRead.string(from:)))
            default:
                break
            }
            guard depth < 80, let children = values[4] as? [AXUIElement] else { continue }
            // Depth-first in document order.
            for child in children.reversed() {
                stack.append((child, depth + 1))
            }
        }
        let key = Self.sourceKey(reading.context)
        return PageContent(
            text: collector.text, nodeCount: nodes, isPartial: partial, capturedAt: now, sourceKey: key)
    }

    public static func sourceKey(_ context: ForegroundContext) -> String {
        "\(context.pid)|\(context.url?.absoluteString ?? context.windowTitle ?? "")"
    }

    private static let skippedRoles: Set<String> = ["AXMenuBar", "AXMenu", "AXMenuItem", "AXScrollBar"]

    private struct WebArea {
        var element: AXUIElement
        var url: String?
        var title: String?
    }

    /// The first AXWebArea below the focused window, without descending into
    /// page content. Browser chrome (menus, links, the omnibox) is skipped so
    /// an edited but unsubmitted address is never mistaken for the page.
    private func findWebArea(in window: AXUIElement, ax: AXRead) throws -> WebArea? {
        var visited = 0
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var index = 0
        while index < queue.count {
            let (element, depth) = queue[index]
            index += 1
            visited += 1
            guard visited <= 500 else { return nil }
            let role = try ax.string(element, kAXRoleAttribute as String)
            if role == "AXWebArea" {
                return WebArea(
                    element: element,
                    url: try ax.string(element, "AXURL"),
                    title: try ax.string(element, kAXTitleAttribute as String)
                )
            }
            if (depth > 0 && role == kAXWindowRole as String) || role == "AXMenuBar" || role == "AXMenu"
                || role == "AXLink" || role == "AXTextField" || role == "AXComboBox" || role == "AXToolbar"
            {
                continue
            }
            guard depth < 14 else { continue }
            for child in try ax.children(element, limit: 200) {
                queue.append((child, depth + 1))
            }
        }
        return nil
    }

    /// Chromium and Electron apps build their web accessibility tree only for
    /// assistive clients. `AXManualAccessibility` asks for it without the
    /// window-animation side effects of `AXEnhancedUserInterface`.
    private func enableWebAccessibilityIfNeeded(_ appElement: AXUIElement, pid: pid_t, bundleID: String) {
        guard !accessibilityEnabledPIDs.contains(pid) else { return }
        accessibilityEnabledPIDs.insert(pid)
        if accessibilityEnabledPIDs.count > 256 { accessibilityEnabledPIDs = [pid] }
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    static func website(_ raw: String) -> URL? {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https", let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }
}

private struct TextCollector {
    let characterBudget: Int
    private(set) var text = ""
    private var lastFragment = ""

    init(characterBudget: Int) {
        self.characterBudget = characterBudget
        text.reserveCapacity(min(characterBudget, 16_384))
    }

    var hasRoom: Bool { text.utf8.count < characterBudget }

    mutating func append(_ fragment: String?) {
        guard let fragment else { return }
        let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        // Headings and links often repeat their child text; skip exact repeats.
        guard !trimmed.isEmpty, trimmed != lastFragment else { return }
        lastFragment = trimmed
        if !text.isEmpty { text.append("\n") }
        text.append(trimmed)
    }
}
