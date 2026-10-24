import EventKit
import Observation
import ScreentimeCore

@MainActor
@Observable
final class FocusCalendar {
    private(set) var permissionMessage: String?
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var refreshedAt = Date.distantPast
    @ObservationIgnored private var cachedProfiles: [FocusProfile] = []
    @ObservationIgnored private var cached: [FocusCalendarOccurrence] = []

    init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) {
            [weak self] _ in
            Task { @MainActor in self?.refreshedAt = .distantPast }
        }
    }

    /// Called only by the calendar toggle, never by launch or polling.
    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            permissionMessage = granted ? nil : "Allow calendar access in System Settings to use calendar Focus."
            refreshedAt = .distantPast
            return granted
        } catch {
            permissionMessage = "Calendar access failed: \(error.localizedDescription)"
            return false
        }
    }

    func occurrences(profiles: [FocusProfile], now: Date) -> [FocusCalendarOccurrence] {
        let enabled = profiles.filter { !($0.calendarTitleContains?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }
        guard !enabled.isEmpty else { cached = []; return [] }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            permissionMessage = "Allow calendar access in System Settings to use calendar Focus."
            cached = []
            return []
        }
        permissionMessage = nil
        if enabled == cachedProfiles, now.timeIntervalSince(refreshedAt) < 30 { return cached }
        cachedProfiles = enabled
        refreshedAt = now
        let start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: 2, to: start) ?? now.addingTimeInterval(172_800)
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
        cached = enabled.flatMap { profile in
            events.compactMap { event -> FocusCalendarOccurrence? in
                guard event.status != .canceled,
                      let phrase = profile.calendarTitleContains,
                      (event.title ?? "").localizedCaseInsensitiveContains(phrase),
                      let eventStart = event.startDate, let eventEnd = event.endDate, eventEnd > eventStart
                else { return nil }
                return FocusCalendarOccurrence(id: event.calendarItemIdentifier, profileID: profile.id,
                                               start: eventStart, end: eventEnd)
            }
        }
        return cached
    }
}
