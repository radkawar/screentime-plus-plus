import AppKit
import SwiftUI

/// A brief, non-activating confirmation near the top of the screen, in the
/// spirit of the system volume HUD. One at a time; never takes focus.
@MainActor
enum Toast {
    private static var panel: ShieldPanel?
    private static var generation = 0

    static func show(title: String, detail: String, symbol: String) {
        let panel = Self.panel ?? ShieldPanel()
        Self.panel = panel
        generation += 1
        let current = generation

        let hosting = NSHostingView(rootView: ToastView(title: title, detail: detail, symbol: symbol))
        hosting.sizingOptions = []
        panel.contentView = hosting
        let size = hosting.fittingSize
        guard let screen = NSScreen.main else { return }
        panel.setFrame(
            CGRect(
                x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - 24,
                width: size.width, height: size.height),
            display: true)

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = reduceMotion ? 1 : 0
        panel.orderFrontRegardless()
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
        }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard current == generation else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = reduceMotion ? 0 : 0.35
                panel.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated {
                    if current == generation { panel.orderOut(nil) }
                }
            }
        }
    }
}

private struct ToastView: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .background(Theme.accentSoft, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.Font.body.weight(.semibold))
                Text(detail).font(Theme.Font.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.leading, Theme.Space.s)
        .padding(.trailing, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
        .padding(Theme.Space.s)
        .accessibilityElement(children: .combine)
    }
}
