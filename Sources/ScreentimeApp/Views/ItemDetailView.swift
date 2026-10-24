import Charts
import ScreentimeCore
import SwiftUI

struct ItemDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let subject: DraftSubject
    var sampleReport: UsageReport?
    var sampleWeek: UsageReport?
    var sampleRules: [Rule]?
    @State private var report: UsageReport?
    @State private var week: UsageReport?
    @State private var editing: Rule?

    private var title: String {
        if let surface = subject.surface { return "\(subject.domain ?? subject.appName) · \(surface)" }
        return subject.domain ?? subject.appName
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(Theme.Font.heading)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(Theme.Space.l)
            Divider()
            ScrollView {
                if let report = sampleReport ?? report, let week = sampleWeek ?? week {
                    content(report: report, week: week)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 240)
                }
            }
        }
        .frame(width: 640, height: 700)
        .task(id: subject) { await load() }
        .sheet(item: $editing) { RuleEditor(rule: $0, isNew: false) }
    }

    private func content(report: UsageReport, week: UsageReport) -> some View {
        let rules = coveringRules(report: report)
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(Format.duration(report.totalSeconds, showSeconds: true))
                    .font(Theme.Font.display(56)).monospacedDigit()
                Text(rangeLabel(report.interval))
                    .font(Theme.Font.body).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionTitle(title: "Seven Days", trailing: Format.duration(week.totalSeconds))
                Chart(week.daily()) { day in
                    BarMark(x: .value("Day", day.day, unit: .day), y: .value("Minutes", day.seconds / 60), width: .ratio(0.6))
                        .foregroundStyle(Theme.accent)
                        .accessibilityLabel(day.day.formatted(.dateTime.weekday(.wide).month().day()))
                        .accessibilityValue(Format.spokenDuration(day.seconds))
                }
                .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.abbreviated)) } }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Theme.hairline)
                        AxisValueLabel { if let minutes = value.as(Double.self) { Text(Format.duration(minutes * 60)) } }
                    }
                }
                .chartXScale(domain: week.interval.start...week.interval.end)
                .frame(height: 144)
            }
            surfaces(report)
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionTitle(title: "Rules for This Item", trailing: rules.isEmpty ? "None" : "\(rules.count)")
                ForEach(rules) { rule in
                    HStack(alignment: .top, spacing: Theme.Space.m) {
                        Image(systemName: rule.symbol).foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            Text(rule.name).font(Theme.Font.body.weight(.medium))
                            Text(rule.targetSummary).font(Theme.Font.caption).foregroundStyle(.secondary)
                            Text((rule.isEnabled ? "" : "Off · ") + rule.summary)
                                .font(Theme.Font.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit") { editing = rule }
                            .buttonStyle(.borderless)
                            .disabled(!model.canEdit(rule))
                    }
                }
                if !rules.contains(where: \.isEnabled) {
                    Text("Choose what happens when you open this.")
                        .font(Theme.Font.body).foregroundStyle(.secondary)
                    HStack(spacing: Theme.Space.s) {
                        Button("Pause…") { draft(.pause) }
                        Button("Limit…") { draft(.limit) }
                        Button("Block…") { draft(.block) }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func surfaces(_ report: UsageReport) -> some View {
        let surfaces = report.items.flatMap(\.surfaces).sorted { $0.seconds > $1.seconds }
        if subject.domain != nil {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionTitle(title: "Pages & Surfaces")
                ForEach(surfaces) { surface in
                    surfaceRow(surface.name, seconds: surface.seconds, total: report.totalSeconds)
                }
                let other = report.totalSeconds - surfaces.reduce(0) { $0 + $1.seconds }
                if other > 0 { surfaceRow("Other Pages", seconds: other, total: report.totalSeconds) }
                if report.totalSeconds == 0 {
                    Text("No time recorded in this range.").font(Theme.Font.body).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func surfaceRow(_ name: String, seconds: TimeInterval, total: TimeInterval) -> some View {
        VStack(spacing: Theme.Space.s) {
            HStack {
                Text(name)
                Spacer()
                Text(Format.duration(seconds, showSeconds: true)).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(Theme.Font.body)
            ProportionBar(fraction: total > 0 ? seconds / total : 0, color: Theme.accent)
        }
        .padding(.vertical, Theme.Space.xs)
    }

    private func coveringRules(report: UsageReport) -> [Rule] {
        let recordedIDs = Set(report.segments.compactMap(\.ruleID))
        let bundles = Set(report.segments.map(\.bundleID)).union([subject.bundleID])
        var urls: [URL?] = [subject.url ?? subject.domain.flatMap { URL(string: "https://\($0)/") }]
        if let domain = subject.domain {
            let names = Set(report.segments.compactMap(\.surface)).union(subject.surface.map { [$0] } ?? [])
            urls += SurfaceCatalog.surfaces.filter {
                DomainName.host(domain, isWithin: $0.domain) && names.contains($0.name)
            }.compactMap { URL(string: "https://" + $0.pattern.raw.replacingOccurrences(of: "*", with: "sample")) }.map(Optional.some)
        }
        return (sampleRules ?? model.configuration.rules).filter { rule in
            if recordedIDs.contains(rule.id) { return true }
            return bundles.contains { bundle in
                urls.contains { url in
                    let context = ForegroundContext(bundleID: bundle, appName: subject.appName, pid: 0, isBrowser: subject.domain != nil, url: url)
                    return PolicyEngine.match(rule: rule, context: context, headline: FoldedText(""), content: nil) != nil
                }
            }
        }
    }

    private func rangeLabel(_ interval: DateInterval) -> String {
        let last = interval.end.addingTimeInterval(-1)
        if Calendar.current.isDate(interval.start, inSameDayAs: last) {
            return "on " + interval.start.formatted(.dateTime.month(.wide).day())
        }
        return interval.start.formatted(.dateTime.month(.abbreviated).day()) + " – " + last.formatted(.dateTime.month(.abbreviated).day())
    }

    private func draft(_ kind: DraftKind) {
        model.presentRuleDraft(RuleDraft.rule(for: subject, kind: kind))
    }

    private func load() async {
        guard sampleReport == nil else { return }
        let calendar = Calendar.current
        let interval = model.itemDetailInterval ?? model.today.report.interval
        let lastDay = calendar.startOfDay(for: interval.end.addingTimeInterval(-1))
        let end = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? interval.end
        let start = calendar.date(byAdding: .day, value: -6, to: lastDay) ?? interval.start
        async let rangeReport = model.history(for: subject, in: interval)
        async let weekReport = model.history(for: subject, in: DateInterval(start: start, end: end))
        (report, week) = await (rangeReport, weekReport)
    }
}
