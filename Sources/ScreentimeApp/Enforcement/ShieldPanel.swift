import AppKit
import SwiftUI

/// Borderless, non-activating panel drawn exactly over an offending window
/// (or the page area of a browser window). It can take keyboard focus for the
/// intention field without activating Screentime++, so the shielded app stays
/// frontmost and focus-driven show/hide loops are impossible.
final class ShieldPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        // Join whatever Space the shielded window is on, including full-screen ones.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Places the shield card, and for apps, plain covers over every other window
/// the app has on screen, so a second window is not a way around a rule.
@MainActor
final class ShieldWindowController {
    private let panel = ShieldPanel()
    private var hosting: NSHostingView<AnyView>?
    private var covers: [ShieldPanel] = []
    private var coverContent: AnyView = AnyView(EmptyView())
    /// Offsets of the covered area inside the tracked window, in points.
    private var insets = NSEdgeInsets()
    /// Set when shielding a whole app: its windows are followed via the window server.
    private var appPID: pid_t?
    private var appTimer: Timer?

    var isVisible: Bool { panel.isVisible }

    /// Show the card. Pass `appPID` to shield every window of a non-browser app.
    func show<Card: View, Cover: View>(
        _ card: Card, cover: Cover, windowFrame: CGRect?, contentFrame: CGRect?, appPID: pid_t?
    ) {
        let root = AnyView(card)
        if let hosting {
            hosting.rootView = root
        } else {
            let view = NSHostingView(rootView: root)
            view.sizingOptions = []
            panel.contentView = view
            hosting = view
        }
        coverContent = AnyView(cover)
        insets = Self.insets(window: windowFrame, content: contentFrame)
        self.appPID = appPID
        if let windowFrame {
            apply(windowFrame: windowFrame)
        } else if let screen = NSScreen.main {
            panel.setFrame(screen.visibleFrame, display: false)
        }
        if !panel.isVisible {
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            panel.alphaValue = reduceMotion ? 1 : 0
            panel.orderFrontRegardless()
            if !reduceMotion {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    panel.animator().alphaValue = 1
                }
            }
        }
        appTimer?.invalidate()
        appTimer = nil
        if appPID != nil {
            refreshAppWindows()
            let timer = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshAppWindows() }
            }
            RunLoop.main.add(timer, forMode: .common)
            appTimer = timer
        }
    }

    /// Align to a new window frame in AX coordinates. No-op when unchanged.
    func apply(windowFrame: CGRect) {
        let covered = CGRect(
            x: windowFrame.minX + insets.left,
            y: windowFrame.minY + insets.top,
            width: windowFrame.width - insets.left - insets.right,
            height: windowFrame.height - insets.top - insets.bottom)
        let frame = Self.cocoaRect(fromAX: covered.width > 0 && covered.height > 0 ? covered : windowFrame)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
    }

    func hide() {
        appTimer?.invalidate()
        appTimer = nil
        appPID = nil
        for cover in covers { cover.orderOut(nil) }
        covers.removeAll()
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        hosting?.rootView = AnyView(EmptyView())
    }

    /// The frontmost window of the app carries the card; the rest get covers.
    private func refreshAppWindows() {
        guard let appPID else { return }
        let frames = Self.windowFrames(pid: appPID)
        if let front = frames.first { apply(windowFrame: front) }
        let others = Array(frames.dropFirst())
        while covers.count < others.count {
            let cover = ShieldPanel()
            cover.contentView = NSHostingView(rootView: coverContent)
            covers.append(cover)
        }
        for (index, cover) in covers.enumerated() {
            if index < others.count {
                let frame = Self.cocoaRect(fromAX: others[index])
                if cover.frame != frame { cover.setFrame(frame, display: true) }
                if !cover.isVisible { cover.orderFrontRegardless() }
            } else if cover.isVisible {
                cover.orderOut(nil)
            }
        }
        // Keep the card above the covers.
        panel.orderFrontRegardless()
    }

    /// On-screen, normal-level windows of `pid`, front to back, in global
    /// top-left coordinates (the same space as Accessibility).
    static func windowFrames(pid: pid_t) -> [CGRect] {
        guard
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                (info[kCGWindowLayer as String] as? Int) == 0,
                let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                let rect = CGRect(dictionaryRepresentation: bounds),
                rect.width >= 80, rect.height >= 60
            else { return nil }
            return rect
        }
    }

    /// Cover the page area only when it is a sensible size, so the address bar
    /// stays usable for going somewhere else.
    private static func insets(window: CGRect?, content: CGRect?) -> NSEdgeInsets {
        guard let window, let content, content.width >= 320, content.height >= 240,
            window.contains(content.insetBy(dx: 1, dy: 1))
        else { return NSEdgeInsets() }
        return NSEdgeInsets(
            top: content.minY - window.minY, left: content.minX - window.minX,
            bottom: window.maxY - content.maxY, right: window.maxX - content.maxX)
    }

    /// AX and the window server use a top-left origin on the primary display; AppKit uses bottom-left.
    static func cocoaRect(fromAX rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
