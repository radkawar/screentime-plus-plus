import SwiftUI
import WidgetKit

private struct TodayEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot?
}

private struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: Date(), snapshot: context.isPreview ? .sample : WidgetSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0), matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(86_400)
        let entries = [
            TodayEntry(date: now, snapshot: WidgetSnapshot.read(now: now)),
            TodayEntry(date: midnight, snapshot: nil),
        ]
        completion(Timeline(entries: entries, policy: .after(min(midnight, now.addingTimeInterval(15 * 60)))))
    }
}

private struct TodayWidgetEntryView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        TodayWidgetView(snapshot: entry.snapshot, isMedium: family == .systemMedium)
            .containerBackground(Theme.canvas, for: .widget)
            .widgetURL(URL(string: "screentimepp://today"))
    }
}

@main
struct ScreentimeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.widgetKind, provider: TodayProvider()) { entry in
            TodayWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Your distracting time, daily goal, and activity on this Mac.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
