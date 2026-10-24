import Foundation

/// An app-specific policy takes precedence over both the global timeout and media assertions.
public enum AppIdleOverride: Codable, Hashable, Sendable {
    case alwaysCountsAsUse
    case idleAfter(minutes: Int)
}

public enum IdlePolicy {
    /// Away/locked screens are handled before this decision and never count as use.
    /// The assertion is evaluated lazily: explicit app policies do not consult IOKit.
    public static func isIdle(
        secondsSinceInput: TimeInterval, globalThreshold: TimeInterval,
        override: AppIdleOverride?, displaySleepIsPrevented: @autoclosure () -> Bool
    ) -> Bool {
        switch override {
        case .alwaysCountsAsUse:
            return false
        case .idleAfter(let minutes):
            return secondsSinceInput >= TimeInterval(max(1, minutes)) * 60
        case nil:
            return secondsSinceInput >= max(30, globalThreshold) && !displaySleepIsPrevented()
        }
    }
}
