import AppKit
import CoreGraphics
import Foundation
import IOKit.pwr_mgt

public struct MonitorSample: @unchecked Sendable {
    public enum State {
        /// Someone is using another app.
        case active(ForegroundReading)
        /// Screentime++ itself is frontmost.
        case own
        /// No input past the idle threshold and no media playing.
        case idle
        /// Screen asleep, locked, or the user session switched out.
        case away
    }

    public var date: Date
    public var state: State
    /// Page or window text, when content inspection is on and the read is current.
    public var content: PageContent?
}

/// Samples the foreground once a second on a private queue and delivers
/// results on the main queue. All Accessibility work stays off the main thread.
public final class ActivityMonitor: @unchecked Sendable {
    public var onSample: (@MainActor (MonitorSample) -> Void)?
    /// Frame updates (AX coordinates) for the window being shielded.
    public var onWindowFrame: (@MainActor (pid_t, CGRect) -> Void)?

    private let queue = DispatchQueue(label: "dev.screentimepp.monitor", qos: .userInitiated)
    private let reader = ForegroundReader()
    private var timer: DispatchSourceTimer?
    private var frameTimer: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []

    // Queue-confined state.
    private var isAway = false
    private var needsContent = false
    private var contentInterval: TimeInterval = 4
    private var idleThreshold: TimeInterval = 120
    private var lastContent: PageContent?
    private var trackedPID: pid_t?
    private var lastFrame: CGRect?

    public init() {}

    public func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(100))
            source.setEventHandler { [weak self] in self?.tick() }
            source.resume()
            timer = source
        }
        let center = NSWorkspace.shared.notificationCenter
        let awayNames: [Notification.Name] = [
            NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification,
            NSWorkspace.willSleepNotification,
        ]
        let backNames: [Notification.Name] = [
            NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification,
            NSWorkspace.didWakeNotification,
        ]
        for name in awayNames {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                    self?.queue.async { self?.isAway = true }
                })
        }
        for name in backNames {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                    self?.queue.async {
                        self?.isAway = false
                        self?.tick()
                    }
                })
        }
        observers.append(
            center.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil
            ) { [weak self] _ in
                self?.refresh()
            })
        // Screen lock is reported through the distributed center.
        let distributed = DistributedNotificationCenter.default()
        observers.append(
            distributed.addObserver(
                forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: nil
            ) { [weak self] _ in
                self?.queue.async { self?.isAway = true }
            })
        observers.append(
            distributed.addObserver(
                forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: nil
            ) { [weak self] _ in
                self?.queue.async {
                    self?.isAway = false
                    self?.tick()
                }
            })
    }

    public func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            frameTimer?.cancel()
            frameTimer = nil
        }
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observers.removeAll()
    }

    public func configure(needsContent: Bool, idleThreshold: TimeInterval) {
        queue.async { [self] in
            self.needsContent = needsContent
            self.idleThreshold = max(30, idleThreshold)
            if !needsContent { lastContent = nil }
        }
    }

    /// Sample now, for example right after the user changes app or a rule.
    public func refresh() {
        queue.async { [weak self] in self?.tick() }
    }

    /// Keep a shield aligned with a window at display rate. Pass nil to stop.
    public func trackWindow(pid: pid_t?) {
        queue.async { [self] in
            guard pid != trackedPID else { return }
            trackedPID = pid
            lastFrame = nil
            frameTimer?.cancel()
            frameTimer = nil
            guard let pid else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now(), repeating: .milliseconds(33), leeway: .milliseconds(5))
            source.setEventHandler { [weak self] in
                guard let self, let frame = reader.focusedWindowFrame(pid: pid), frame != lastFrame else { return }
                lastFrame = frame
                let handler = onWindowFrame
                DispatchQueue.main.async { MainActor.assumeIsolated { handler?(pid, frame) } }
            }
            source.resume()
            frameTimer = source
        }
    }

    private func tick() {
        let now = Date()
        let state: MonitorSample.State
        var content: PageContent?
        if isAway {
            state = .away
        } else if let app = NSWorkspace.shared.frontmostApplication {
            if app.processIdentifier == getpid() {
                state = .own
            } else if let id = app.bundleIdentifier, Self.awayBundleIDs.contains(id) {
                state = .away
            } else if let id = app.bundleIdentifier, Self.transientBundleIDs.contains(id) {
                // A permission prompt over the shielded app: not use, and not leaving.
                state = .idle
            } else if isIdle(frontmostPID: app.processIdentifier) {
                state = .idle
            } else {
                let reading = reader.read(app)
                state = .active(reading)
                if needsContent, reading.isComplete {
                    content = currentContent(for: reading, now: now)
                }
            }
        } else {
            state = .away
        }
        let sample = MonitorSample(date: now, state: state, content: content)
        let handler = onSample
        DispatchQueue.main.async { MainActor.assumeIsolated { handler?(sample) } }
    }

    private func currentContent(for reading: ForegroundReading, now: Date) -> PageContent? {
        let key = ForegroundReader.sourceKey(reading.context)
        if let lastContent, lastContent.sourceKey == key,
            now.timeIntervalSince(lastContent.capturedAt) < contentInterval
        {
            return lastContent
        }
        let fresh = reader.inspectContent(reading, now: now)
        lastContent = fresh
        return fresh
    }

    private func isIdle(frontmostPID: pid_t) -> Bool {
        let anyInput = CGEventType(rawValue: ~0)!
        let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        guard seconds >= idleThreshold else { return false }
        // Watching a video is use, not idleness. Browsers often hold the
        // assertion from a helper process, so any holder counts.
        return !Self.displaySleepIsPrevented()
    }

    static func displaySleepIsPrevented() -> Bool {
        var status: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess,
            let values = status?.takeRetainedValue() as? [String: NSNumber]
        else { return false }
        return (values["PreventUserIdleDisplaySleep"]?.intValue ?? 0) > 0
    }

    /// Frontmost while the Mac is locked or the screen saver runs; not use.
    static let awayBundleIDs: Set<String> = [
        "com.apple.loginwindow", "com.apple.ScreenSaver.Engine", "com.apple.screensaver",
    ]

    /// System prompts that briefly take the foreground on top of the user's app.
    static let transientBundleIDs: Set<String> = [
        "com.apple.accessibility.universalAccessAuthWarn", "com.apple.UserNotificationCenter",
        "com.apple.coreservices.uiagent", "com.apple.SecurityAgent",
    ]
}
