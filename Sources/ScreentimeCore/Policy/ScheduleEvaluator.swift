import Foundation

public enum ScheduleEvaluator {
    public static func isActive(_ schedule: RuleSchedule, at date: Date, calendar: Calendar) -> Bool {
        switch schedule {
        case .always: true
        case .duringFocus: false
        case .windows(let windows): windows.contains { contains($0, date: date, calendar: calendar) }
        }
    }

    public static func contains(_ window: ScheduleWindow, date: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        let minute = minuteOfDay(date, calendar: calendar)
        let previous = weekday == 1 ? 7 : weekday - 1
        if window.startMinute == window.endMinute {
            return window.weekdays.contains(weekday)
        }
        if window.startMinute < window.endMinute {
            return window.weekdays.contains(weekday)
                && minute >= window.startMinute && minute < window.endMinute
        }
        // Overnight: the evening of a listed day, or the early morning after one.
        return (window.weekdays.contains(weekday) && minute >= window.startMinute)
            || (window.weekdays.contains(previous) && minute < window.endMinute)
    }

    /// End of the window containing `date`, for "until 17:00" copy. Nil when
    /// the schedule is always on or the date is outside every window.
    public static func currentWindowEnd(_ schedule: RuleSchedule, at date: Date, calendar: Calendar) -> Date? {
        guard case .windows(let windows) = schedule else { return nil }
        let startOfDay = calendar.startOfDay(for: date)
        let minute = minuteOfDay(date, calendar: calendar)
        let ends = windows.filter { contains($0, date: date, calendar: calendar) }.compactMap {
            window -> Date? in
            if window.startMinute == window.endMinute {
                return calendar.date(byAdding: .day, value: 1, to: startOfDay)
            }
            let dayOffset = (window.endMinute <= window.startMinute && minute >= window.startMinute) ? 1 : 0
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfDay) else { return nil }
            return calendar.date(byAdding: .minute, value: window.endMinute, to: day)
        }
        return ends.max()
    }

    static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
