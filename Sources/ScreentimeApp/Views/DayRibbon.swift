import ScreentimeCore
import SwiftUI

/// Signature detail for Today: one 24-hour band. Each stretch of use is drawn
/// in its category colour; distracting time is solid, everything else is
/// lighter, and an ember tick marks now. Hover to read a stretch.
struct DayRibbon: View {
    let segments: [Segment]
    let day: Date
    var now: Date = Date()
    var height: CGFloat = 40
    var showsLabels = true
    var isInteractive = true

    @State private var hover: Hover?
    @State private var width: CGFloat = 0

    private struct Hover: Equatable {
        var x: CGFloat
        var segment: Segment
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                Canvas { context, size in draw(in: &context, size: size) }
                if let hover {
                    tooltip(for: hover.segment)
                        .fixedSize()
                        .alignmentGuide(.leading) { dimensions in
                            -(min(max(0, hover.x - dimensions.width / 2), width - dimensions.width))
                        }
                        .offset(y: -34)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .frame(height: height)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard isInteractive else { return }
                switch phase {
                case .active(let location):
                    if let segment = segment(at: location.x, width: width) {
                        hover = Hover(x: location.x, segment: segment)
                    } else {
                        hover = nil
                    }
                case .ended:
                    hover = nil
                }
            }
            if showsLabels {
                HStack {
                    ForEach(Array(stride(from: 0, through: 24, by: 6)), id: \.self) { hour in
                        Text(label(hour))
                            .font(Theme.Font.caption)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                        if hour < 24 { Spacer(minLength: 0) }
                    }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Today\u{2019}s activity across 24 hours")
        .accessibilityValue(accessibilitySummary)
    }

    private var dayStart: Date { Calendar.current.startOfDay(for: day) }

    private func x(for date: Date, width: CGFloat) -> CGFloat {
        CGFloat(date.timeIntervalSince(dayStart) / 86_400) * width
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let radius = min(8, size.height / 4)
        let band = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: radius, style: .continuous)
        context.fill(band, with: .color(Theme.track))
        context.clip(to: band)

        // Quarter-day guides.
        for hour in [6, 12, 18] {
            let gx = size.width * CGFloat(hour) / 24
            context.fill(Path(CGRect(x: gx - 0.25, y: 0, width: 0.5, height: size.height)), with: .color(Theme.hairline))
        }

        for segment in segments {
            let x0 = x(for: segment.start, width: size.width)
            let x1 = max(x0 + 0.75, x(for: segment.end, width: size.width))
            let isFocused = hover?.segment.id == segment.id
            let opacity = segment.ruleID == nil ? 0.42 : 1
            context.fill(
                Path(CGRect(x: x0, y: 0, width: x1 - x0, height: size.height)),
                with: .color(Theme.color(for: segment.category).opacity(isFocused ? 1 : opacity)))
        }

        if Calendar.current.isDate(now, inSameDayAs: day) {
            let nx = x(for: now, width: size.width)
            context.fill(Path(CGRect(x: nx - 1, y: 0, width: 2, height: size.height)), with: .color(Theme.ember))
        }
    }

    private func segment(at location: CGFloat, width: CGFloat) -> Segment? {
        guard width > 0 else { return nil }
        let time = dayStart.addingTimeInterval(TimeInterval(location / width) * 86_400)
        // Accept a few pixels of slack so thin stretches are reachable.
        let slack = 86_400 / Double(width) * 3
        return segments.min { lhs, rhs in
            distance(lhs, time) < distance(rhs, time)
        }.flatMap { distance($0, time) <= slack ? $0 : nil }
    }

    private func distance(_ segment: Segment, _ time: Date) -> TimeInterval {
        if time < segment.start { return segment.start.timeIntervalSince(time) }
        if time > segment.end { return time.timeIntervalSince(segment.end) }
        return 0
    }

    private func tooltip(for segment: Segment) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.color(for: segment.category)).frame(width: 7, height: 7)
            Text(segment.domain ?? segment.appName).font(Theme.Font.label)
            Text("\(Format.clock(segment.start))\u{2013}\(Format.clock(segment.end))")
                .font(Theme.Font.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
    }

    private func label(_ hour: Int) -> String {
        switch hour {
        case 0, 24: "12 AM"
        case 12: "Noon"
        default: hour < 12 ? "\(hour) AM" : "\(hour - 12) PM"
        }
    }

    private var accessibilitySummary: String {
        let total = segments.reduce(0) { $0 + $1.duration }
        return "\(Format.spokenDuration(total)) of use"
    }
}
