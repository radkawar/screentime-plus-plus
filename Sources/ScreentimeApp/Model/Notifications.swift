import Foundation
import Observation
import ScreentimeCore
import UserNotifications

/// Authorization is requested by NotificationSettings only, never by sampling or launch.
@MainActor
@Observable
final class Notifications {
    private(set) var problem: String?
    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var goalBeingAdded: String?
    @ObservationIgnored private let deliveryDelegate = NotificationDeliveryDelegate()
    private static let prefix = "screentime."
    private static let goalDayKey = "notifications.lastGoalReminderDay"

    init() {
        center.delegate = deliveryDelegate
    }

    func requestAuthorization() async -> Bool {
        do {
            let allowed = try await center.requestAuthorization(options: [.alert, .sound])
            problem = allowed ? nil : "Notifications are off in System Settings."
            return allowed
        } catch {
            problem = error.localizedDescription
            return false
        }
    }

    func isAuthorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    func reconcile(configuration: AppConfiguration, today: TodaySummary, now: Date = Date()) {
        revision += 1
        let requestedRevision = revision
        Task { [weak self] in
            guard let self else { return }
            let authorized = await isAuthorized()
            let pending = await center.pendingNotificationRequests()
            guard revision == requestedRevision else { return }
            let settings = configuration.settings
            var desired: [String: UNNotificationRequest] = [:]
            if authorized && settings.weeklyReviewNotifications == true {
                let id = Self.prefix + "weekly"
                let content = UNMutableNotificationContent()
                content.title = "Your Weekly Review Is Ready"
                content.body = "See your week in perspective in History → This Week."
                var components = DateComponents()
                components.weekday = 1
                components.hour = 18
                components.minute = 0
                desired[id] = UNNotificationRequest(identifier: id, content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true))
            }
            if authorized && settings.sessionEndingNotifications == true {
                for grant in configuration.grants where grant.kind == .session {
                    let remaining = grant.until.timeIntervalSince(now)
                    guard remaining > 0 else { continue }
                    // The expiry is part of the identity: extending a session cancels its old reminder.
                    let id = Self.prefix + "session.\(grant.ruleID).\(grant.until.timeIntervalSince1970)"
                    if remaining <= 60 {
                        if let request = pending.first(where: { $0.identifier == id }) { desired[id] = request }
                        continue
                    }
                    let content = UNMutableNotificationContent()
                    content.title = "1 Minute Left"
                    let rule = configuration.rules.first { $0.id == grant.ruleID }?.name ?? "Your session"
                    content.body = "\(rule) will pause again in 1 minute."
                    desired[id] = UNNotificationRequest(identifier: id, content: content,
                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: remaining - 60, repeats: false))
                }
            }
            let day = Calendar.current.startOfDay(for: now)
            let goalID = Self.prefix + "goal.\(day.timeIntervalSince1970)"
            let goal = Double(settings.dailyGoalMinutes) * 60
            let isToday = Calendar.current.isDate(today.report.interval.start, inSameDayAs: now)
            let shouldRemind = authorized && settings.goalNotifications == true && isToday && goal > 0
                && today.report.distractingSeconds >= goal * 0.8
            // A pending immediate reminder survives a routine refresh, but not disabling its toggle.
            if shouldRemind, let existing = pending.first(where: { $0.identifier == goalID }) {
                desired[goalID] = existing
            }
            let obsolete = pending.map(\.identifier).filter { $0.hasPrefix(Self.prefix) && desired[$0] == nil }
            center.removePendingNotificationRequests(withIdentifiers: obsolete)
            let existing = Set(pending.map(\.identifier))
            for (id, request) in desired where !existing.contains(id) {
                add(request)
            }
            if shouldRemind && UserDefaults.standard.string(forKey: Self.goalDayKey) != goalID && goalBeingAdded != goalID {
                goalBeingAdded = goalID
                let content = UNMutableNotificationContent()
                content.title = "You’ve Reached 80% of Your Daily Goal"
                let minutes = max(0, Int(ceil((goal - today.report.distractingSeconds) / 60)))
                content.body = "\(minutes) minutes remain in your distracting-time goal today."
                let request = UNNotificationRequest(identifier: goalID, content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
                center.add(request) { [weak self] error in
                    Task { @MainActor in
                        guard let self else { return }
                        self.goalBeingAdded = nil
                        if let error { self.problem = error.localizedDescription }
                        else { UserDefaults.standard.set(goalID, forKey: Self.goalDayKey) }
                    }
                }
            }
        }
    }

    private func add(_ request: UNNotificationRequest) {
        center.add(request) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in self?.problem = error.localizedDescription }
        }
    }
}

private final class NotificationDeliveryDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}
