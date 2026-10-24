import AppKit
import OSLog
import ScreentimeCore
import ServiceManagement

@MainActor
final class FocusKeepaliveAgent {
    static let shared = FocusKeepaliveAgent()
    private let service = SMAppService.agent(plistName: "dev.screentimepp.keepalive.plist")
    private let log = Logger(subsystem: "dev.screentimepp.app", category: "focus-keepalive")
    private var desiredActive = false
    private var reconciliation: Task<Void, Never>?

    /// QA copies must neither register a real-data guard nor unregister the installed one.
    private var isIsolated: Bool {
        !(ProcessInfo.processInfo.environment["SCREENTIME_DATA_DIR"] ?? "").isEmpty
            || CommandLine.arguments.contains("--qa-gallery")
    }

    static func exitIfAlreadyRunning() {
        // Isolated QA copies use their own data and may run beside the real app.
        guard (ProcessInfo.processInfo.environment["SCREENTIME_DATA_DIR"] ?? "").isEmpty,
            let bundleID = Bundle.main.bundleIdentifier
        else { return }
        let pid = ProcessInfo.processInfo.processIdentifier
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains(where: { $0.processIdentifier != pid && !$0.isTerminated }) {
            // Do not instantiate the model, touch persistence, or show a quit alert.
            exit(EXIT_SUCCESS)
        }
    }

    func synchronize(focus: FocusSession?) {
        guard !isIsolated else { return }
        desiredActive = FocusGuardDecision.evaluate(focus: focus, appIsRunning: true, at: Date()) != .stop
        guard reconciliation == nil else { return }
        reconciliation = Task {
            defer { reconciliation = nil }
            repeat {
                let active = desiredActive
                do {
                    if active {
                        if service.status == .notRegistered { try service.register() }
                        if service.status != .enabled {
                            log.warning("Locked Focus relaunch protection requires background-item approval in System Settings.")
                        }
                    } else if service.status != .notRegistered && service.status != .notFound {
                        try await service.unregister()
                    }
                } catch {
                    log.error("Cannot update Focus guard registration: \(error.localizedDescription, privacy: .public)")
                }
                if desiredActive == active { break }
            } while !Task.isCancelled
        }
    }
}
