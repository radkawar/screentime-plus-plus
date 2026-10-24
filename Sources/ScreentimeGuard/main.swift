import AppKit
import OSLog
import ScreentimeCore

/// A separate launchd-owned process can supervise an app opened by Finder too.
@MainActor
final class FocusSupervisor {
    private let log = Logger(subsystem: "dev.screentimepp.app", category: "focus-guard")
    private let configuration: ConfigStore
    private let applicationURL: URL
    private var opening = false

    init() throws {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        configuration = ConfigStore(url: support.appendingPathComponent("Screentime++/configuration.json"))
        // The signed helper is embedded beside the app executable in Contents/MacOS.
        applicationURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func check() {
        do {
            let focus = try configuration.load()?.focus
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.screentimepp.app")
                .contains { !$0.isTerminated }
            switch FocusGuardDecision.evaluate(focus: focus, appIsRunning: running, at: Date()) {
            case .stop:
                // SuccessfulExit=false prevents restart churn after the lock expires.
                exit(EXIT_SUCCESS)
            case .wait:
                break
            case .relaunch:
                guard !opening else { return }
                opening = true
                let options = NSWorkspace.OpenConfiguration()
                options.activates = false
                options.addsToRecentItems = false
                NSWorkspace.shared.openApplication(at: applicationURL, configuration: options) { [weak self] _, error in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            self?.opening = false
                            if let error { self?.log.error("Cannot reopen Screentime++: \(error.localizedDescription, privacy: .public)") }
                        }
                    }
                }
            }
        } catch {
            log.error("Cannot read locked Focus: \(error.localizedDescription, privacy: .public)")
            // launchd retries failed reads or a crashed guard, not an expired lock.
            exit(EXIT_FAILURE)
        }
    }
}

MainActor.assumeIsolated {
    do {
        let supervisor = try FocusSupervisor()
        supervisor.check()
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { supervisor.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.run()
    } catch {
        Logger(subsystem: "dev.screentimepp.app", category: "focus-guard")
            .error("Cannot start Focus guard: \(error.localizedDescription, privacy: .public)")
        exit(EXIT_FAILURE)
    }
}
