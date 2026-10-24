import ScreentimeCore
import SwiftUI

/// A compact, single-line label. Never wraps: a chip that breaks mid-word is a bug.
struct Chip: View {
    let title: String
    var symbol: String?
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            }
            Text(title).font(.system(size: 11, weight: .medium))
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(minHeight: 20)
        .foregroundStyle(.secondary)
        .background(Theme.track(contrast), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

/// Lays children out left to right, breaking to a new line only between
/// children, each at its ideal size.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// App icon for apps; a quiet lettered tile in the category colour for sites,
/// and for apps that are no longer installed.
struct SubjectIcon: View {
    let bundleID: String
    var domain: String?
    var category: UsageCategory = .other
    var size: CGFloat = 28
    /// Name used for the monogram when an app's icon is unavailable.
    var name: String?

    var body: some View {
        Group {
            if let domain {
                monogram(domain)
            } else if let icon = IconCache.icon(bundleID: bundleID) {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                monogram(name ?? bundleID.split(separator: ".").last.map(String.init) ?? "?")
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func monogram(_ text: String) -> some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(Theme.color(for: category).opacity(0.16))
            .overlay {
                Text(text.first.map { String($0).uppercased() } ?? "?")
                    .font(.system(size: size * 0.48, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.color(for: category))
            }
    }
}

/// A choice among a few values (durations, session lengths). The selected
/// pill is filled with the accent and stays legible when the window is
/// inactive, unlike tinted system buttons.
struct PillButtonStyle: ButtonStyle {
    let isSelected: Bool
    var compact = false
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font((compact ? Theme.Font.caption : Theme.Font.body).weight(.medium))
            .monospacedDigit()
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, compact ? Theme.Space.s : Theme.Space.m)
            .frame(minWidth: compact ? 36 : 64, minHeight: compact ? 22 : 30)
            .background(Capsule().fill(isSelected ? Theme.accent : Theme.track(contrast)))
            .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Theme.hairline(contrast), lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
            .accessibilityAddTraits(isSelected ? .isSelected : [])
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
    var color: Color = Theme.accent
    var height: CGFloat = 4
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Capsule()
            .fill(Theme.track(contrast))
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
            SubjectIcon(bundleID: item.bundleID, domain: item.domain, category: item.category, name: item.title)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text(item.title).font(Theme.Font.body.weight(.medium)).lineLimit(1)
                    if item.isDistracting {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.accent)
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
        .accessibilityValue(
            (item.isDistracting ? "Covered by a rule. " : "")
                + item.surfaces.map { "\($0.name), \(Format.spokenDuration($0.seconds))" }.joined(separator: ". "))
    }
}

extension Rule {
    /// "Pause · 10 s, +5 s each open · 45 min / day"
    var summary: String {
        var parts: [String] = []
        switch response {
        case .track: parts.append("Track")
        case .pause(let pause):
            parts.append(
                pause.escalationSeconds > 0
                    ? "Pause \(pause.waitSeconds)s, +\(pause.escalationSeconds)s each open" : "Pause \(pause.waitSeconds)s")
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
