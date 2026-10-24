import ScreentimeCore
import SwiftUI

struct FocusView: View {
    @Environment(AppModel.self) private var model
    @State private var minutes = 50
    @State private var selected: Set<UUID> = []
    @State private var locks = false
    @State private var title = "Deep work"

    private static let durations = [25, 50, 90, 180]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                if let focus = model.activeFocus {
                    running(focus)
                } else {
                    setup
                }
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.l)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Focus")
        .onAppear(perform: seedSelection)
    }

    private func seedSelection() {
        guard selected.isEmpty else { return }
        selected = Set(
            model.configuration.rules.filter { rule in
                if case .duringFocus = rule.schedule { return true }
                if case .track = rule.response { return false }
                return rule.isEnabled
            }.map(\.id))
    }

    // MARK: Running

    private func running(_ focus: FocusSession) -> some View {
        VStack(alignment: .center, spacing: Theme.Space.l) {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                FocusArc(progress: 1 - focus.progress(at: timeline.date), remaining: focus.end.timeIntervalSince(timeline.date))
            }
            .frame(width: 260, height: 260)
            .frame(maxWidth: .infinity)
            VStack(spacing: Theme.Space.xs) {
                Text(focus.title).font(Theme.Font.title)
                Text("Until \(Format.clock(focus.end))\(focus.isLocked ? " \u{00B7} Locked" : "")")
                    .font(Theme.Font.body)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionTitle(title: "Blocking")
                ForEach(model.configuration.rules.filter { focus.ruleIDs.contains($0.id) }) { rule in
                    Label(rule.name, systemImage: rule.symbol)
                        .font(Theme.Font.body)
                }
            }
            .frame(maxWidth: 360, alignment: .leading)
            if focus.isLocked {
                Label("This session can\u{2019}t be ended early.", systemImage: "lock.fill")
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
            } else {
                Button("End Focus") { model.endFocus() }
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Setup

    private var setup: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Start a focus session").font(Theme.Font.display(40))
                Text("Everything below is blocked until the session ends. Pauses and sessions are skipped.")
                    .font(Theme.Font.body).foregroundStyle(.secondary)
            }
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
            HStack(spacing: Theme.Space.s) {
                ForEach(Self.durations, id: \.self) { value in
                    Button {
                        minutes = value
                    } label: {
                        Text(Format.minutesLabel(value))
                            .font(Theme.Font.body.weight(.medium))
                            .monospacedDigit()
                            .frame(minWidth: 64, minHeight: 30)
                    }
                    .buttonStyle(.bordered)
                    .tint(minutes == value ? Theme.ember : nil)
                    .accessibilityAddTraits(minutes == value ? .isSelected : [])
                }
                Stepper(value: $minutes, in: 5...480, step: 5) {
                    Text(Format.minutesLabel(minutes)).monospacedDigit().frame(minWidth: 52)
                }
                .fixedSize()
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionTitle(title: "Block", trailing: "\(selected.count) rules")
                VStack(spacing: 0) {
                    ForEach(model.configuration.rules) { rule in
                        Toggle(isOn: binding(rule.id)) {
                            HStack(spacing: Theme.Space.s) {
                                Image(systemName: rule.symbol).foregroundStyle(Theme.ember).frame(width: 20)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(rule.name)
                                    Text(rule.targetSummary).font(Theme.Font.caption).foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(.vertical, 6)
                        if rule.id != model.configuration.rules.last?.id { Divider() }
                    }
                }
            }
            Toggle(isOn: $locks) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lock the session")
                    Text("No overrides and no ending early. Quitting Screentime++ is refused until it ends.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            Button {
                model.startFocus(
                    minutes: minutes, ruleIDs: Array(selected), locked: locks,
                    title: title.trimmingCharacters(in: .whitespaces).isEmpty ? "Focus" : title)
            } label: {
                Text("Start \(Format.minutesLabel(minutes)) Focus").frame(minWidth: 180)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selected.isEmpty)
        }
    }

    private func binding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { selected.contains(id) },
            set: { isOn in if isOn { selected.insert(id) } else { selected.remove(id) } })
    }
}

/// Signature for Focus: one ember arc that drains as the session runs.
struct FocusArc: View {
    let progress: Double
    let remaining: TimeInterval

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, style: StrokeStyle(lineWidth: 10))
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(Theme.ember, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
            VStack(spacing: 2) {
                Text(Format.countdown(remaining))
                    .font(Theme.Font.display(48))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                Text("remaining").font(Theme.Font.caption).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .accessibilityElement()
        .accessibilityLabel("Focus, \(Format.spokenDuration(remaining)) remaining")
    }
}
