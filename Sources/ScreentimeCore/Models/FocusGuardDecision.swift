import Foundation

/// Whether the locked-Focus supervisor should stay alive or reopen the app.
public enum FocusGuardDecision: Equatable, Sendable {
    case stop
    case wait
    case relaunch

    public static func evaluate(focus: FocusSession?, appIsRunning: Bool, at date: Date) -> Self {
        guard let focus, focus.isLocked, focus.isActive(at: date) else { return .stop }
        return appIsRunning ? .wait : .relaunch
    }
}
