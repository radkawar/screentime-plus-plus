import ScreentimeCore
import SwiftUI

struct RuleEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var rule: Rule
    @State private var composing: TargetList?
    @State private var confirmsDelete = false
    let isNew: Bool

    enum TargetList: String, Identifiable {
        case targets
        case exceptions
        var id: String { rawValue }
    }

    init(rule: Rule, isNew: Bool) {
        _rule = State(initialValue: rule)
        self.isNew = isNew
    }

    private var isEditable: Bool { isNew || model.canEdit(rule) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                whatSection
                exceptSection
                whenSection
                responseSection
                limitsSection
            }
            .formStyle(.grouped)
            .disabled(!isEditable)
            footer
        }
        .frame(width: 580, height: 720)
        .sheet(item: $composing) { list in
            TargetComposer { target in
                switch list {
                case .targets: rule.targets.append(target)
                case .exceptions: rule.exceptions.append(target)
                }
                composing = nil
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Theme.Space.m) {
            Menu {
                ForEach(Self.symbols, id: \.self) { symbol in
                    Button {
                        rule.symbol = symbol
                    } label: {
                        Label(symbol, systemImage: symbol).labelStyle(.iconOnly)
                    }
                }
            } label: {
                Image(systemName: rule.symbol)
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.ember)
                    .frame(width: 40, height: 40)
                    .background(Theme.emberSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .help("Choose a symbol")
            .disabled(!isEditable)
            TextField("Name", text: $rule.name)
                .textFieldStyle(.plain)
                .font(Theme.Font.title)
                .disabled(!isEditable)
            Spacer()
            liveMatch
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.l)
        .padding(.bottom, Theme.Space.s)
    }

    /// Tests the draft against whatever is in front right now.
    @ViewBuilder
    private var liveMatch: some View {
        if let context = model.live.context {
            let matched =
                PolicyEngine.match(
                    rule: rule, context: context, headline: FoldedText(context.headline), content: model.live.content)
                != nil
            Label(
                matched ? "Matches \(context.domain ?? context.appName)" : "No match for \(context.domain ?? context.appName)",
                systemImage: matched ? "checkmark.circle.fill" : "circle.dashed"
            )
            .font(Theme.Font.caption)
            .foregroundStyle(matched ? Theme.ember : .secondary)
            .lineLimit(1)
            .frame(maxWidth: 200, alignment: .trailing)
            .help("Checked against the last app or page you used")
        }
    }

    // MARK: Sections

    private var whatSection: some View {
        Section {
            TargetRows(targets: $rule.targets)
            Button {
                composing = .targets
            } label: {
                Label("Add App, Site, Page or Phrase\u{2026}", systemImage: "plus")
            }
            .buttonStyle(.link)
        } header: {
            Text("What")
        } footer: {
            Text("Pages and phrases are checked against the address, title and visible text of the page in front.")
                .font(Theme.Font.caption).foregroundStyle(.secondary)
        }
    }

    private var exceptSection: some View {
        Section("Except") {
            TargetRows(targets: $rule.exceptions)
            Button {
                composing = .exceptions
            } label: {
                Label("Add Exception\u{2026}", systemImage: "plus")
            }
            .buttonStyle(.link)
        }
    }

    private enum ScheduleKind: Hashable {
        case always
        case windows
        case focus
    }

    private var scheduleKind: Binding<ScheduleKind> {
        Binding {
            switch rule.schedule {
            case .always: .always
            case .windows: .windows
            case .duringFocus: .focus
            }
        } set: { kind in
            switch kind {
            case .always: rule.schedule = .always
            case .focus: rule.schedule = .duringFocus
            case .windows:
                if case .windows = rule.schedule { return }
                rule.schedule = .windows([
                    ScheduleWindow(weekdays: ScheduleWindow.workdays, startMinute: 9 * 60, endMinute: 17 * 60)
                ])
            }
        }
    }

    private var whenSection: some View {
        Section("When") {
            Picker("Active", selection: scheduleKind) {
                Text("All the time").tag(ScheduleKind.always)
                Text("On a schedule").tag(ScheduleKind.windows)
                Text("Only during Focus").tag(ScheduleKind.focus)
            }
            if case .windows(let windows) = rule.schedule {
                ForEach(windows) { window in
                    ScheduleWindowEditor(
                        window: Binding(
                            get: { window },
                            set: { updated in
                                guard case .windows(var all) = rule.schedule,
                                    let index = all.firstIndex(where: { $0.id == window.id })
                                else { return }
                                all[index] = updated
                                rule.schedule = .windows(all)
                            }),
                        canRemove: windows.count > 1,
                        remove: {
                            guard case .windows(var all) = rule.schedule else { return }
                            all.removeAll { $0.id == window.id }
                            rule.schedule = .windows(all)
                        })
                }
                Button {
                    guard case .windows(var all) = rule.schedule else { return }
                    all.append(ScheduleWindow(weekdays: [1, 7], startMinute: 10 * 60, endMinute: 18 * 60))
                    rule.schedule = .windows(all)
                } label: {
                    Label("Add Time Window", systemImage: "plus")
                }
                .buttonStyle(.link)
            }
        }
    }

    private enum ResponseKind: Hashable {
        case track
        case pause
        case block
    }

    private var responseKind: Binding<ResponseKind> {
        Binding {
            switch rule.response {
            case .track: .track
            case .pause: .pause
            case .block: .block
            }
        } set: { kind in
            switch kind {
            case .track: rule.response = .track
            case .pause: if case .pause = rule.response {} else { rule.response = .pause(PauseSettings()) }
            case .block: if case .block = rule.response {} else { rule.response = .block(BlockSettings()) }
            }
        }
    }

    private var responseSection: some View {
        Section {
            Picker("Response", selection: responseKind) {
                Text("Track").tag(ResponseKind.track)
                Text("Pause").tag(ResponseKind.pause)
                Text("Block").tag(ResponseKind.block)
            }
            .pickerStyle(.segmented)
            switch rule.response {
            case .track:
                Text("Count time and opens. Nothing appears unless a limit below is reached.")
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
            case .pause(let settings):
                pauseControls(settings)
            case .block(let settings):
                blockControls(settings)
            }
        } header: {
            Text("Response")
        }
    }

    private func pauseControls(_ settings: PauseSettings) -> some View {
        let binding = Binding<PauseSettings>(
            get: { settings }, set: { rule.response = .pause($0) })
        return Group {
            Stepper(value: binding.waitSeconds, in: 3...60, step: 1) {
                LabeledContent("Wait", value: "\(settings.waitSeconds) seconds")
            }
            Stepper(value: binding.escalationSeconds, in: 0...30, step: 1) {
                LabeledContent("Longer each open by", value: "\(settings.escalationSeconds) seconds")
            }
            LabeledContent("Sessions offered") {
                HStack(spacing: Theme.Space.xs) {
                    ForEach([1, 2, 5, 10, 15, 30], id: \.self) { minutes in
                        let isOn = settings.sessionMinutes.contains(minutes)
                        Button("\(minutes)m") {
                            var next = Set(settings.sessionMinutes)
                            if isOn, next.count > 1 { next.remove(minutes) } else { next.insert(minutes) }
                            binding.wrappedValue.sessionMinutes = next.sorted()
                        }
                        .buttonStyle(.bordered)
                        .tint(isOn ? Theme.ember : nil)
                        .controlSize(.small)
                    }
                }
            }
            Toggle("Ask what I\u{2019}m here for", isOn: binding.asksIntention)
        }
    }

    private func blockControls(_ settings: BlockSettings) -> some View {
        let binding = Binding<BlockSettings>(get: { settings }, set: { rule.response = .block($0) })
        return Group {
            Toggle("Allow a one-minute override (press and hold)", isOn: binding.allowsOverride)
            Toggle("Close the tab or quit the app automatically", isOn: binding.closesAutomatically)
        }
    }

    private var limitsSection: some View {
        Section {
            OptionalStepper(
                title: "Daily time", value: $rule.limits.dailyMinutes, range: 5...600, step: 5, defaultValue: 30
            ) { "\(Format.minutesLabel($0))" }
            OptionalStepper(
                title: "Daily opens", value: $rule.limits.dailyOpens, range: 1...100, step: 1, defaultValue: 10
            ) { "\($0) opens" }
        } header: {
            Text("Limits")
        } footer: {
            Text("Past a limit, this rule blocks until tomorrow.")
                .font(Theme.Font.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if !isNew {
                Button("Delete Rule", role: .destructive) { confirmsDelete = true }
                    .disabled(!isEditable)
                    .confirmationDialog(
                        "Delete \u{201C}\(rule.name)\u{201D}?", isPresented: $confirmsDelete
                    ) {
                        Button("Delete", role: .destructive) {
                            model.delete(rule: rule)
                            dismiss()
                        }
                    } message: {
                        Text("Its history stays in Today and History.")
                    }
            }
            if !isEditable {
                Label("Locked", systemImage: "lock.fill").font(Theme.Font.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button(isNew ? "Add Rule" : "Save") {
                model.save(rule: rule)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!isEditable || rule.targets.isEmpty || rule.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(Theme.Space.m)
        .background(.bar)
    }

    static let symbols = [
        "hand.raised", "wind", "moon", "brain.head.profile", "play.rectangle", "bubble.left", "newspaper",
        "bag", "gamecontroller", "suit.club", "eye.slash", "flame", "leaf", "book", "timer", "bell.slash",
    ]
}

private struct TargetRows: View {
    @Binding var targets: [Target]

    var body: some View {
        if targets.isEmpty {
            Text("None").foregroundStyle(.secondary)
        }
        ForEach(targets) { target in
            HStack(spacing: Theme.Space.s) {
                targetIcon(target)
                VStack(alignment: .leading, spacing: 1) {
                    Text(target.displayName).lineLimit(2)
                    Text(detail(target)).font(Theme.Font.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    targets.removeAll { $0.id == target.id }
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove")
                .accessibilityLabel("Remove \(target.displayName)")
            }
        }
    }

    @ViewBuilder
    private func targetIcon(_ target: Target) -> some View {
        if case .app(let bundleID, _) = target {
            SubjectIcon(bundleID: bundleID, size: 20)
        } else {
            Image(systemName: target.symbol)
                .frame(width: 20, height: 20)
                .foregroundStyle(.secondary)
        }
    }

    private func detail(_ target: Target) -> String {
        switch target {
        case .app: "App"
        case .website: "Website and its subdomains"
        case .urlPattern: "Page"
        case .category: "Installed apps in this category, and known sites"
        case .content(let rule):
            "\(rule.scope == .pageText ? "Text" : "Title and address") \u{00B7} at least \(rule.minimumMatches) mention\(rule.minimumMatches == 1 ? "" : "s")"
                + (rule.apps.isEmpty ? " \u{00B7} any app" : " \u{00B7} in \(rule.apps.map(Self.appName).joined(separator: ", "))")
        }
    }

    private static func appName(_ bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
            ?? bundleID
    }
}

private struct ScheduleWindowEditor: View {
    @Binding var window: ScheduleWindow
    let canRemove: Bool
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { day in
                    let isOn = window.weekdays.contains(day)
                    Button {
                        if isOn { window.weekdays.remove(day) } else { window.weekdays.insert(day) }
                    } label: {
                        Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                            .font(Theme.Font.label)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(isOn ? Color.white : .primary)
                            .background(Circle().fill(isOn ? Theme.ember : Theme.track))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                    .accessibilityValue(isOn ? "On" : "Off")
                }
                Spacer()
                if canRemove {
                    Button(action: remove) { Image(systemName: "minus.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                        .help("Remove this window")
                }
            }
            HStack {
                DatePicker("From", selection: minuteBinding(\.startMinute), displayedComponents: .hourAndMinute)
                DatePicker("to", selection: minuteBinding(\.endMinute), displayedComponents: .hourAndMinute)
                if window.endMinute <= window.startMinute {
                    Text("next day").font(Theme.Font.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func minuteBinding(_ keyPath: WritableKeyPath<ScheduleWindow, Int>) -> Binding<Date> {
        Binding {
            Calendar.current.date(
                bySettingHour: window[keyPath: keyPath] / 60, minute: window[keyPath: keyPath] % 60, second: 0,
                of: Date()) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            window[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }
}

private struct OptionalStepper: View {
    let title: String
    @Binding var value: Int?
    let range: ClosedRange<Int>
    let step: Int
    let defaultValue: Int
    let format: (Int) -> String

    var body: some View {
        HStack {
            Toggle(
                title,
                isOn: Binding(get: { value != nil }, set: { value = $0 ? (value ?? defaultValue) : nil }))
            Spacer()
            if let current = value {
                Stepper(
                    value: Binding(get: { current }, set: { value = $0 }), in: range, step: step
                ) {
                    Text(format(current)).monospacedDigit()
                }
                .fixedSize()
            }
        }
    }
}
