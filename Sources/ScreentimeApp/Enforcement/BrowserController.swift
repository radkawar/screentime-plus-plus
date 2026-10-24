import AppKit
import Carbon.HIToolbox
import Foundation

/// Tab actions for the browser behind a shield.
///
/// Parking (replacing the tab with a blank page, then restoring it) needs
/// Apple Events and works in Safari and the Chromium family. Closing a tab or
/// going back uses a keystroke sent to the browser process, which only needs
/// Accessibility.
@MainActor
final class BrowserController {
    private let queue = DispatchQueue(label: "dev.screentimepp.applescript", qos: .userInitiated)

    static let blankAddress = "about:blank"

    private enum Dialect {
        case safari
        case chromium
    }

    private static func dialect(for bundleID: String) -> Dialect? {
        switch bundleID {
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
            .safari
        case "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary", "com.google.Chrome.dev",
            "org.chromium.Chromium", "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi",
            "company.thebrowser.Browser":
            .chromium
        default:
            nil
        }
    }

    static func canPark(bundleID: String) -> Bool { dialect(for: bundleID) != nil }

    /// Replace the front tab's page. Completion reports whether the browser accepted.
    func setFrontTabAddress(_ address: String, bundleID: String, completion: @escaping @MainActor (Bool) -> Void) {
        guard let dialect = Self.dialect(for: bundleID) else {
            completion(false)
            return
        }
        let escaped = address.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let tab = dialect == .safari ? "current tab" : "active tab"
        let source = """
            tell application id "\(bundleID)"
                if (count of windows) > 0 then set URL of \(tab) of front window to "\(escaped)"
            end tell
            """
        queue.async {
            var error: NSDictionary?
            let script = NSAppleScript(source: source)
            _ = script?.executeAndReturnError(&error)
            let succeeded = error == nil
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(succeeded) } }
        }
    }

    func closeTab(pid: pid_t) {
        send(key: CGKeyCode(kVK_ANSI_W), flags: .maskCommand, to: pid)
    }

    func goBack(pid: pid_t) {
        send(key: CGKeyCode(kVK_ANSI_LeftBracket), flags: .maskCommand, to: pid)
    }

    private func send(key: CGKeyCode, flags: CGEventFlags, to pid: pid_t) {
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown) else { continue }
            event.flags = flags
            event.postToPid(pid)
        }
    }
}
