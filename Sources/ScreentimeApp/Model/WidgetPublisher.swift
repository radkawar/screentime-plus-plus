import Foundation
import OSLog
import ScreentimeCore
import WidgetKit

/// Writes only the current day's compact report, never the history database.
enum WidgetPublisher {
    private static let log = Logger(subsystem: "dev.screentimepp.app", category: "widget")

    static func publish(report: UsageReport, goalSeconds: TimeInterval) {
        // QA and isolated runs must not replace the real widget's data.
        guard ProcessInfo.processInfo.environment["SCREENTIME_DATA_DIR"] == nil,
            !CommandLine.arguments.contains("--qa-gallery")
        else { return }
        guard let container = WidgetSnapshot.containerURL else {
            log.error("Shared widget container is unavailable; check the signing team's App Group entitlement.")
            return
        }
        let dayStart = Calendar.current.startOfDay(for: report.interval.start)
        let snapshot = WidgetSnapshot(
            date: report.interval.end,
            distractingSeconds: report.distractingSeconds,
            goalSeconds: goalSeconds,
            totalSeconds: report.totalSeconds,
            ribbon: report.segments.map {
                .init(start: $0.start.timeIntervalSince(dayStart), end: $0.end.timeIntervalSince(dayStart),
                      category: $0.category.rawValue, distracting: $0.ruleID != nil)
            },
            topItems: report.items.prefix(3).map {
                .init(title: $0.title, seconds: $0.seconds, category: $0.category.rawValue)
            })
        do {
            try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(
                to: container.appendingPathComponent(WidgetSnapshot.fileName), options: .atomic)
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.widgetKind)
        } catch {
            log.error("Widget snapshot could not be saved: \(error.localizedDescription, privacy: .public)")
        }
    }
}
