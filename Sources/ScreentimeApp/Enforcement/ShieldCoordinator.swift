import AppKit
import Observation
import ScreentimeCore
import SwiftUI

/// State shown on the shield card.
@MainActor
@Observable
final class ShieldPresentation: Identifiable {
    enum Phase: Equatable {
        case waiting
        case choosing
    }

    let id = UUID()
    private(set) var intervention: Intervention
    let appName: String
    let subject: String
    let isBrowser: Bool
    let shownAt: Date
    var intention = ""
    private(set) var phase: Phase
    private(set) var remaining: TimeInterval
    /// The tab was replaced by a blank page and will be restored on continue.
    var isParked = false

    private var timer: Timer?

    init(intervention: Intervention, context: ForegroundContext, now: Date) {
        self.intervention = intervention
        appName = context.appName
        subject = context.surface.map { "\(context.domain ?? context.appName) \u{00B7} \($0)" }
            ?? context.domain ?? context.appName
        isBrowser = context.isBrowser
        shownAt = now
        if case .pause(let pause) = intervention {
            remaining = TimeInterval(pause.waitSeconds)
            phase = pause.waitSeconds > 0 ? .waiting : .choosing
        } else {
            remaining = 0
            phase = .choosing
        }
    }

    var rule: Rule { intervention.match.rule }

    var pause: PauseIntervention? {
        if case .pause(let pause) = intervention { return pause }
        return nil
    }

    var block: BlockIntervention? {
        if case .block(let block) = intervention { return block }
        return nil
    }

    func update(_ intervention: Intervention) {
        // Keep the running countdown; only refresh the facts.
        self.intervention = intervention
    }

    func startClock() {
        guard phase == .waiting, timer == nil else { return }
        let started = Date()
        let initial = remaining
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.remaining = max(0, initial - Date().timeIntervalSince(started))
                if self.remaining <= 0 {
                    self.phase = .choosing
                    self.stopClock()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopClock() {
        timer?.invalidate()
        timer = nil
    }
}

/// How a shield ended.
enum ShieldResolution: Equatable {
    case continued(minutes: Int)
    case overridden
    /// The shielded content went away (another tab, app, or the screen locked).
    case turnedBack
    /// The user chose a card action that walks away: close, hide, quit, go back.
    case declined
    case closedAutomatically
    /// Enforcement was suspended (rules paused): restore the page, grant nothing.
    case released
}

/// Decides when the shield appears, stays and leaves, and performs the tab or
/// app action that goes with each outcome.
@MainActor
final class ShieldCoordinator {
    struct Active {
        var presentation: ShieldPresentation
        var pid: pid_t
        var bundleID: String
        var ruleID: UUID
        var subject: String
        var originalURL: URL?
        var recordID: Int64?
    }

    private(set) var active: Active?
    private let window = ShieldWindowController()
    private let browser = BrowserController()
    private var autoCloseTask: Task<Void, Never>?

    var parksTabs = true
    /// Called once per shield with its outcome, for grants and the log.
    var onResolve: ((Active, ShieldResolution) -> Void)?
    /// Called when a new shield appears; returns the intervention log ID.
    var onPresent: ((ShieldPresentation, ForegroundContext) -> Int64?)?
    /// Start or stop window tracking for frame alignment.
    var onTrack: ((pid_t?) -> Void)?

    var presentation: ShieldPresentation? { active?.presentation }

    /// Apply a fresh evaluation for the frontmost window.
    func update(intervention: Intervention?, reading: ForegroundReading, now: Date) {
        let context = reading.context
        guard let intervention else {
            guard let active else { return }
            // A parked tab reads as a blank page; that is still the shielded tab.
            if active.pid == context.pid, active.originalURL != nil, context.url == nil {
                return
            }
            resolve(.turnedBack)
            return
        }
        let rule = intervention.match.rule
        if let active, active.pid == context.pid, active.ruleID == rule.id, active.subject == context.subject {
            active.presentation.update(intervention)
            return
        }
        if active != nil { resolve(.turnedBack) }
        present(intervention, reading: reading, now: now)
    }

    /// Something other than the shielded window took over (another app, our
    /// own window, the screen locking).
    func foregroundLeft() {
        if active != nil { resolve(.turnedBack) }
    }

    /// Lift the current shield and give back any parked tab, for example when
    /// every rule is paused from the menu bar.
    func release() {
        if active != nil { resolve(.released) }
    }

    /// Keep the panel aligned while the window moves.
    func windowMoved(pid: pid_t, frame: CGRect) {
        guard active?.pid == pid else { return }
        window.apply(windowFrame: frame)
    }

    // MARK: Card actions

    func choose(minutes: Int) {
        resolve(.continued(minutes: minutes))
    }

    func overrideOneMinute() {
        resolve(.overridden)
    }

    func closeTabOrHide() {
        guard let active else { return }
        if active.presentation.isBrowser {
            browser.closeTab(pid: active.pid)
        } else {
            NSRunningApplication(processIdentifier: active.pid)?.hide()
        }
        resolve(.declined)
    }

    /// Quit the shielded app. Apps with unsaved work still ask as usual.
    func quitApp() {
        guard let active, !active.presentation.isBrowser else { return }
        NSRunningApplication(processIdentifier: active.pid)?.terminate()
        resolve(.declined)
    }

    func goBack() {
        guard let active else { return }
        if active.presentation.isBrowser, active.originalURL == nil {
            browser.goBack(pid: active.pid)
        }
        resolve(.declined)
    }

    // MARK: Private

    private func present(_ intervention: Intervention, reading: ForegroundReading, now: Date) {
        let context = reading.context
        let presentation = ShieldPresentation(intervention: intervention, context: context, now: now)
        var active = Active(
            presentation: presentation, pid: context.pid, bundleID: context.bundleID,
            ruleID: intervention.match.rule.id, subject: context.subject, originalURL: nil, recordID: nil)
        active.recordID = onPresent?(presentation, context)
        self.active = active

        if context.isBrowser, parksTabs, let url = context.url, BrowserController.canPark(bundleID: context.bundleID) {
            self.active?.originalURL = url
            presentation.isParked = true
            browser.setFrontTabAddress(BrowserController.blankAddress, bundleID: context.bundleID, pid: context.pid) {
                [weak self] accepted in
                guard let self, !accepted, self.active?.presentation.id == presentation.id else { return }
                // Automation was refused: fall back to cover-only.
                self.active?.originalURL = nil
                presentation.isParked = false
            }
        }

        window.show(
            ShieldCard(presentation: presentation, coordinator: self),
            cover: ShieldCover(ruleName: intervention.match.rule.name, symbol: intervention.match.rule.symbol),
            windowFrame: reading.windowFrame, contentFrame: reading.contentFrame,
            appPID: context.isBrowser ? nil : context.pid)
        // Browsers track the focused window through AX; apps through the window server.
        onTrack?(context.isBrowser ? context.pid : nil)
        presentation.startClock()

        if case .block(let block) = intervention, block.closesAutomatically {
            autoCloseTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(1_600))
                guard let self, !Task.isCancelled, self.active?.presentation.id == presentation.id else { return }
                if presentation.isBrowser {
                    self.browser.closeTab(pid: context.pid)
                } else {
                    NSRunningApplication(processIdentifier: context.pid)?.terminate()
                }
                self.resolve(.closedAutomatically)
            }
        }
    }

    private func resolve(_ resolution: ShieldResolution) {
        guard let active else { return }
        autoCloseTask?.cancel()
        autoCloseTask = nil
        active.presentation.stopClock()
        self.active = nil
        window.hide()
        onTrack?(nil)
        browser.cancelPendingNavigation()

        switch resolution {
        case .continued, .overridden, .released:
            if let original = active.originalURL {
                browser.setFrontTabAddress(original.absoluteString, bundleID: active.bundleID, pid: active.pid) { _ in }
            }
        case .turnedBack, .declined, .closedAutomatically:
            break
        }
        onResolve?(active, resolution)
    }
}
