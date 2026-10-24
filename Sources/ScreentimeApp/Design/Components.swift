import ScreentimeCore
import SwiftUI

/// App icon for apps; a quiet lettered tile in the category colour for sites.
struct SubjectIcon: View {
    let bundleID: String
    var domain: String?
    var category: UsageCategory = .other
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let domain {
                let letter = domain.first.map { String($0).uppercased() } ?? "?"
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(Theme.color(for: category).opacity(0.16))
                    .overlay {
                        Text(letter)
                            .font(.system(size: size * 0.48, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.color(for: category))
                    }
            } else if let icon = IconCache.icon(bundleID: bundleID) {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(Theme.track)
                    .overlay { Image(systemName: "app").foregroundStyle(.secondary) }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct SectionTitle: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Theme.Font.heading)
            Spacer()
            if let trailing {
                Text(trailing).font(Theme.Font.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// A thin proportional bar; the track is always visible so zero reads as zero.
struct ProportionBar: View {
    let fraction: Double
    var color: Color = Theme.ember
    var height: CGFloat = 4

    var body: some View {
        Capsule()
            .fill(Theme.track)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(color)
                    .scaleEffect(x: max(0.004, min(1, fraction)), y: 1, anchor: .leading)
            }
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

struct UsageRow: View {
    let item: UsageTotal
    let maxSeconds: TimeInterval

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            SubjectIcon(bundleID: item.bundleID, domain: item.domain, category: item.category)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text(item.title).font(Theme.Font.body.weight(.medium)).lineLimit(1)
                    if item.isDistracting {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.ember)
                            .help("Covered by a rule")
                    }
                    Spacer(minLength: Theme.Space.s)
                    Text(Format.duration(item.seconds, showSeconds: true))
                        .font(Theme.Font.body)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                ProportionBar(
                    fraction: maxSeconds > 0 ? item.seconds / maxSeconds : 0, color: Theme.color(for: item.category))
                if !item.surfaces.isEmpty {
                    Text(
                        item.surfaces.prefix(3).map { "\($0.name) \(Format.duration($0.seconds, showSeconds: true))" }
                            .joined(separator: "  \u{00B7}  ")
                    )
                    .font(Theme.Font.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title), \(Format.spokenDuration(item.seconds))")
    }
}

extension Rule {
    /// "Pause · 10 s, +5 s each open · 45 min / day"
    var summary: String {
        var parts: [String] = []
        switch response {
        case .track: parts.append("Track")
        case .pause(let pause): parts.append("Pause \(pause.waitSeconds)s, +\(pause.escalationSeconds)s each open")
        case .block(let block): parts.append(block.closesAutomatically ? "Block and close" : "Block")
        }
        switch schedule {
        case .always: break
        case .duringFocus: parts.append("During Focus")
        case .windows(let windows):
            parts.append(windows.count == 1 ? windows[0].summary : "\(windows.count) schedules")
        }
        if let minutes = limits.dailyMinutes { parts.append("\(Format.minutesLabel(minutes)) a day") }
        if let opens = limits.dailyOpens { parts.append("\(opens) opens a day") }
        return parts.joined(separator: " \u{00B7} ")
    }

    var targetSummary: String {
        guard !targets.isEmpty else { return "Nothing yet" }
        let names = targets.prefix(3).map(\.displayName)
        let more = targets.count > 3 ? " and \(targets.count - 3) more" : ""
        return names.joined(separator: ", ") + more
    }
}

extension ScheduleWindow {
    var summary: String {
        let days: String
        switch weekdays {
        case ScheduleWindow.everyDay: days = "Every day"
        case ScheduleWindow.workdays: days = "Weekdays"
        case [1, 7]: days = "Weekends"
        default:
            let symbols = Calendar.current.shortWeekdaySymbols
            days = weekdays.sorted().map { symbols[$0 - 1] }.joined(separator: " ")
        }
        return "\(days) \(Self.time(startMinute))\u{2013}\(Self.time(endMinute))"
    }

    static func time(_ minute: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
        return Format.clock(date)
    }
}
