import Charts
import ScreentimeCore
import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var range: Range = .week
    @State private var report: UsageReport?
    @State private var interventions: [InterventionRecord] = []
    @State private var selectedDay: Date?
    @State private var showsWeeklyReview = false

    enum Range: Int, CaseIterable, Identifiable {
        case week = 7
        case month = 30
        var id: Int { rawValue }
        var title: String { self == .week ? "7 Days" : "30 Days" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                if let report {
                    let days = report.daily()
                    summary(days: days)
                    chart(days: days)
                    breakdown(report)
                    intentions
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.l)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Range", selection: $range) {
                    ForEach(Range.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("History Date Range")
                .frame(width: 180)
            }
            ToolbarItem {
                Button("This Week", systemImage: "calendar") { showsWeeklyReview = true }
                    .buttonStyle(.borderless)
            }
        }
        .task(id: range) { await load() }
        .sheet(isPresented: $showsWeeklyReview) { WeeklyReviewSheet().environment(model) }
    }

    private func load() async {
        let (report, interventions) = await model.history(days: range.rawValue)
        self.report = report
        self.interventions = interventions
    }

    private func summary(days: [DayTotal]) -> some View {
        let active = days.filter { $0.seconds > 0 }
        let average = active.isEmpty ? 0 : active.reduce(0) { $0 + $1.distractingSeconds } / Double(active.count)
        let goal = TimeInterval(model.configuration.settings.dailyGoalMinutes * 60)
        let withinGoal = active.filter { $0.distractingSeconds <= goal }.count
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("DAILY AVERAGE")
                .font(Theme.Font.label).foregroundStyle(.secondary).tracking(0.6)
            Text(Format.duration(average))
                .font(Theme.Font.display(56))
                .monospacedDigit()
            Text(
                active.isEmpty
                    ? "No recorded days in this range yet."
                    : "distracting per day. \(withinGoal) of \(active.count) day\(active.count == 1 ? "" : "s") inside your \(Format.duration(goal)) goal."
            )
            .font(Theme.Font.body)
            .foregroundStyle(.secondary)
        }
    }

    private func chart(days: [DayTotal]) -> some View {
        let goal = Double(model.configuration.settings.dailyGoalMinutes) / 60
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: 6) {
                Spacer()
                Capsule()
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .frame(width: 18, height: 1.5)
                Text("Daily goal \u{00B7} \(Format.duration(goal * 3600))")
                    .font(Theme.Font.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Chart {
                ForEach(days) { day in
                    ForEach(UsageCategory.allCases) { category in
                        let hours = (day.byCategory[category] ?? 0) / 3600
                        if hours > 0 {
                            BarMark(
                                x: .value("Day", day.day, unit: .day),
                                y: .value("Hours", hours),
                                width: .ratio(0.62)
                            )
                            .foregroundStyle(by: .value("Category", category.title))
                            .opacity(selectedDay == nil || Calendar.current.isDate(day.day, inSameDayAs: selectedDay!) ? 1 : 0.35)
                        }
                    }
                }
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            .chartForegroundStyleScale(
                domain: UsageCategory.allCases.map(\.title),
                range: UsageCategory.allCases.map(Theme.color(for:))
            )
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: range == .week ? 1 : 5)) { _ in
                    AxisValueLabel(format: range == .week ? .dateTime.weekday(.abbreviated) : .dateTime.day().month(.abbreviated))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel {
                        if let hours = value.as(Double.self) { Text(Format.duration(hours * 3600)) }
                    }
                }
            }
            .chartXScale(domain: chartDomain(days))
            .chartXSelection(value: $selectedDay)
            .chartLegend(position: .bottom, alignment: .leading, spacing: Theme.Space.m)
            .frame(height: 240)
            if let selectedDay, let day = days.first(where: { Calendar.current.isDate($0.day, inSameDayAs: selectedDay) }) {
                Text(
                    "\(day.day.formatted(.dateTime.weekday(.wide).day().month())): \(Format.duration(day.seconds)) on screen, \(Format.duration(day.distractingSeconds)) distracting"
                )
                .font(Theme.Font.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
    }

    /// The whole range, so a single recorded day is one bar among empty days.
    private func chartDomain(_ days: [DayTotal]) -> ClosedRange<Date> {
        let calendar = Calendar.current
        let first = days.first?.day ?? calendar.startOfDay(for: Date())
        let last = days.last?.day ?? first
        return first...(calendar.date(byAdding: .day, value: 1, to: last) ?? last)
    }

    private func breakdown(_ report: UsageReport) -> some View {
        let items = Array(report.items.prefix(12))
        let maxSeconds = items.first?.seconds ?? 1
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionTitle(title: "Most used", trailing: Format.duration(report.totalSeconds))
            if items.isEmpty {
                Text("Nothing recorded in this range.").font(Theme.Font.body).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(items) { item in
                    UsageRow(item: item, maxSeconds: maxSeconds)
                    if item.id != items.last?.id { Divider().padding(.leading, 44) }
                }
            }
        }
    }

    @ViewBuilder
    private var intentions: some View {
        let stated = interventions.filter { $0.intention != nil }
        if !stated.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionTitle(title: "What you said you were there for", trailing: "\(stated.count)")
                VStack(spacing: 0) {
                    ForEach(stated.prefix(20)) { record in
                        InterventionRow(record: record)
                        if record.id != stated.prefix(20).last?.id { Divider() }
                    }
                }
            }
        }
    }
}
