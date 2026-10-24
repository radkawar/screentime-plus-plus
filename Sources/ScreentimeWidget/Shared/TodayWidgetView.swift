import ScreentimeCore
import SwiftUI

/// Shared verbatim with the host's QA gallery, using the app's Theme tokens.
struct TodayWidgetView: View {
    let snapshot: WidgetSnapshot?
    var isMedium = false
    @Environment(\.colorSchemeContrast) private var contrast

    private var isOverGoal: Bool {
        guard let snapshot else { return false }
        return snapshot.distractingSeconds > snapshot.goalSeconds
    }
    private var tint: Color { isOverGoal ? Theme.caution : Theme.accent }

    var body: some View {
        Group {
            if let snapshot {
                HStack(spacing: Theme.Space.m) {
                    goal(snapshot)
                        .frame(maxWidth: isMedium ? 128 : .infinity)
                    if isMedium {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            HStack {
                                Text("Today").font(.system(size: 12, weight: .semibold))
                                Spacer(minLength: Theme.Space.xs)
                                Text("\(Format.duration(snapshot.totalSeconds)) total")
                                    .font(Theme.Font.caption).foregroundStyle(.secondary)
                            }
                            ribbon(snapshot)
                            if snapshot.topItems.isEmpty {
                                Text("No activity yet").font(Theme.Font.caption).foregroundStyle(.secondary)
                            } else {
                                ForEach(0..<min(3, snapshot.topItems.count), id: \.self) { index in
                                    let item = snapshot.topItems[index]
                                    HStack(spacing: Theme.Space.xs) {
                                        Circle().fill(categoryColor(item.category)).frame(width: 4, height: 4)
                                        Text(item.title).lineLimit(1)
                                        Spacer(minLength: Theme.Space.xs)
                                        Text(Format.duration(item.seconds)).foregroundStyle(.secondary)
                                    }
                                    .font(Theme.Font.caption)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .monospacedDigit()
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Image(systemName: "chart.pie").font(.title2).foregroundStyle(Theme.accent)
                    Text("Your day, so far").font(Theme.Font.display(20))
                    Text("Open Screentime++ to update today's activity.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }

    private func goal(_ snapshot: WidgetSnapshot) -> some View {
        VStack(spacing: Theme.Space.xs) {
            ZStack {
                Circle().stroke(Theme.track(contrast), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: min(1, max(0, snapshot.distractingSeconds / max(1, snapshot.goalSeconds))))
                    .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(Format.duration(snapshot.distractingSeconds)).font(Theme.Font.display(24))
                        .minimumScaleFactor(0.7).lineLimit(1)
                    Text("distracting").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .padding(Theme.Space.s)
            }
            .frame(width: 96, height: 96)
            Text("\(Format.duration(snapshot.goalSeconds)) goal")
                .font(Theme.Font.caption).foregroundStyle(.secondary)
            if isOverGoal {
                Label("Over goal", systemImage: "exclamationmark.circle")
                    .font(.system(size: 10)).foregroundStyle(Theme.caution)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today: \(Format.spokenDuration(snapshot.distractingSeconds)) distracting, \(Format.spokenDuration(snapshot.goalSeconds)) goal\(isOverGoal ? ", over goal" : "")")
    }

    private func ribbon(_ snapshot: WidgetSnapshot) -> some View {
        VStack(spacing: Theme.Space.xs) {
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.track(contrast)))
                let calendar = Calendar.current
                let start = calendar.startOfDay(for: snapshot.date)
                let dayLength = (calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)).timeIntervalSince(start)
                for segment in snapshot.ribbon {
                    let x = max(0, min(1, segment.start / dayLength)) * size.width
                    let end = max(0, min(1, segment.end / dayLength)) * size.width
                    context.fill(
                        Path(CGRect(x: x, y: 0, width: max(1, end - x), height: size.height)),
                        with: .color(categoryColor(segment.category)))
                    if segment.distracting {
                        context.fill(Path(CGRect(x: x, y: size.height - 2, width: max(1, end - x), height: 2)), with: .color(.primary))
                    }
                }
            }
            .frame(height: 16).clipShape(RoundedRectangle(cornerRadius: 4))
            HStack {
                Text("00")
                Spacer()
                Text("12")
                Spacer()
                Text("24")
            }
            .font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today's activity across 24 hours. Distracting activity is underlined.")
    }

    private func categoryColor(_ category: String) -> Color {
        Theme.color(for: UsageCategory(rawValue: category) ?? .other)
    }
}
