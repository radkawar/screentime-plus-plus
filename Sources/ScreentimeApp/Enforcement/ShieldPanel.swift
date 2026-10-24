import AppKit
import SwiftUI

/// Borderless, non-activating panel drawn exactly over the offending window
/// (or the page area of a browser window). It can take keyboard focus for the
/// intention field without activating Screentime++, so the browser stays the
/// frontmost app and focus-driven show/hide loops are impossible.
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
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .transient]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ShieldWindowController {
    private let panel = ShieldPanel()
    private var hosting: NSHostingView<AnyView>?
    /// Offsets of the covered area inside the tracked window, in points.
    private var insets = NSEdgeInsets()

    var isVisible: Bool { panel.isVisible }

    func show<Content: View>(_ content: Content, windowFrame: CGRect?, contentFrame: CGRect?) {
        let root = AnyView(content)
        if let hosting {
            hosting.rootView = root
        } else {
            let view = NSHostingView(rootView: root)
            view.sizingOptions = []
            panel.contentView = view
            hosting = view
        }
        insets = Self.insets(window: windowFrame, content: contentFrame)
        if let windowFrame {
            apply(windowFrame: windowFrame)
        } else if let screen = NSScreen.main {
            panel.setFrame(screen.visibleFrame, display: false)
        }
        guard !panel.isVisible else { return }
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
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        hosting?.rootView = AnyView(EmptyView())
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

    /// AX uses a top-left origin on the primary display; AppKit uses bottom-left.
    static func cocoaRect(fromAX rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
