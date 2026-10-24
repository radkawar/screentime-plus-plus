import AppKit
import Carbon.HIToolbox
import Foundation

/// Tab actions for the browser behind a shield.
///
/// Safari and Chromium use Apple Events. Firefox-family browsers use
/// Accessibility keystrokes, without activating or typing into another app.
@MainActor
final class BrowserController {
    private let queue = DispatchQueue(label: "dev.screentimepp.applescript", qos: .userInitiated)
    private var keyboardNavigation: Task<Void, Never>?

    static let blankAddress = "about:blank"

    private enum Dialect {
        case safari
        case chromium
        case firefox
    }

    private static func dialect(for bundleID: String) -> Dialect? {
        switch bundleID {
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
            .safari
        case "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary", "com.google.Chrome.dev",
            "org.chromium.Chromium", "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi",
            "company.thebrowser.Browser":
            .chromium
        case "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "app.zen-browser.zen":
            .firefox
        default:
            nil
        }
    }

    static func canPark(bundleID: String) -> Bool { dialect(for: bundleID) != nil }

    /// Replace the front tab's page. Firefox reports event delivery, not page loading.
    func setFrontTabAddress(
        _ address: String, bundleID: String, pid: pid_t, completion: @escaping @MainActor (Bool) -> Void
    ) {
        guard let dialect = Self.dialect(for: bundleID) else {
            completion(false)
            return
        }
        if dialect == .firefox {
            navigateByKeyboard(to: address, pid: pid, completion: completion)
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

    private func navigateByKeyboard(
        to address: String, pid: pid_t, completion: @escaping @MainActor (Bool) -> Void
    ) {
        keyboardNavigation?.cancel()
        keyboardNavigation = Task {
            guard !Task.isCancelled, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                send(key: CGKeyCode(kVK_ANSI_L), flags: .maskCommand, to: pid)
            else {
                completion(false)
                return
            }
            do {
                // Let the address field receive focus before delivering Unicode text.
                try await Task.sleep(for: .milliseconds(80))
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                    completion(false)
                    return
                }
                let source = CGEventSource(stateID: .privateState)
                let characters = Array(address.utf16)
                let sent = characters.withUnsafeBufferPointer { buffer -> Bool in
                    var offset = 0
                    while offset < buffer.count {
                        // Keep each event small and never split a surrogate pair.
                        var count = min(20, buffer.count - offset)
                        if offset + count < buffer.count, (0xD800...0xDBFF).contains(buffer[offset + count - 1]) {
                            count -= 1
                        }
                        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
                        else { return false }
                        for event in [down, up] {
                            event.flags = []
                            event.keyboardSetUnicodeString(stringLength: count, unicodeString: buffer.baseAddress! + offset)
                            event.postToPid(pid)
                        }
                        offset += count
                    }
                    return true
                }
                guard sent else {
                    completion(false)
                    return
                }
                try await Task.sleep(for: .milliseconds(40))
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                    completion(false)
                    return
                }
                completion(send(key: CGKeyCode(kVK_Return), flags: [], to: pid))
            } catch {
                completion(false)
            }
        }
    }

    func cancelPendingNavigation() {
        keyboardNavigation?.cancel()
        keyboardNavigation = nil
    }

    func closeTab(pid: pid_t) {
        cancelPendingNavigation()
        send(key: CGKeyCode(kVK_ANSI_W), flags: .maskCommand, to: pid)
    }

    func goBack(pid: pid_t) {
        cancelPendingNavigation()
        send(key: CGKeyCode(kVK_ANSI_LeftBracket), flags: .maskCommand, to: pid)
    }

    @discardableResult
    private func send(key: CGKeyCode, flags: CGEventFlags, to pid: pid_t) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
        let source = CGEventSource(stateID: .privateState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return false }
        for event in [down, up] {
            event.flags = flags
            event.postToPid(pid)
        }
        return true
    }
}
