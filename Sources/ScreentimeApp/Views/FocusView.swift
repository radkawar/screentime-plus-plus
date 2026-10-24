import ScreentimeCore
import SwiftUI

struct FocusView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = FocusProfile(name: "Writing")
    @State private var composing = false
    @State private var includesRules = false
    @State private var calendarEnabled = false
    @State private var calendarPhrase = ""
    @State private var requestingCalendar = false
    @State private var seeded = false
    var isGallery = false

    private var profiles: [FocusProfile] { isGallery ? [] : model.focusProfiles }
    private var rules: [Rule] { isGallery ? [] : model.configuration.rules }

    private static let categories: [(UsageCategory, String)] = [
        (.social, "Social"), (.entertainment, "Video"), (.communication, "Chat"),
        (.reading, "News"), (.shopping, "Shopping"), (.games, "Games"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                if !isGallery, let focus = model.activeFocus {
                    FocusRunningView(focus: focus, rules: rules,
                                     extend: { model.extendFocus(minutes: 15) }, end: { model.endFocus() })
                } else {
                    setup
                }
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Focus")
        .onAppear {
            guard !seeded else { return }
            seeded = true
            if !profiles.isEmpty { load(model.defaultFocusProfile) }
        }
        .sheet(isPresented: $composing) {
            TargetComposer { target in
                if !draft.targets.contains(target) { draft.targets.append(target) }
                composing = false
            }
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("What needs your attention?").font(Theme.Font.display(40))
                Text("Choose what to block while you focus. You don’t need to create rules first.")
                    .font(Theme.Font.body).foregroundStyle(.secondary)
            }
            if !profiles.isEmpty {
                FocusProfilesView(
                    profiles: profiles, defaultID: model.defaultFocusProfile.id,
                    start: { model.startFocus(profile: $0) }, edit: load,
                    makeDefault: { model.saveFocusProfile($0, makeDefault: true) },
                    delete: { model.deleteFocusProfile($0) })
            }
            TextField("Profile name, such as Writing or Study", text: $draft.name)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 360)
            HStack(spacing: Theme.Space.s) {
                ForEach([25, 50, 90, 180], id: \.self) { value in
                    Button(Format.minutesLabel(value)) { draft.minutes = value }
                        .buttonStyle(PillButtonStyle(isSelected: draft.minutes == value))
                }
                Stepper(value: $draft.minutes, in: 5...480, step: 5) {
                    Text(Format.minutesLabel(draft.minutes)).monospacedDigit()
                }.fixedSize()
            }
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionTitle(title: "Block distractions")
                FlowLayout(spacing: Theme.Space.m) {
                    ForEach(Self.categories, id: \.0) { category, title in
                        Toggle(title, isOn: categoryBinding(category)).toggleStyle(.checkbox)
                    }
                }
                ForEach(draft.targets) { target in
                    HStack {
                        Label(target.displayName, systemImage: target.symbol)
                        Spacer()
                        Button("Remove", systemImage: "minus.circle") {
                            draft.targets.removeAll { $0.id == target.id }
                        }.labelStyle(.iconOnly).buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(target.displayName)")
                    }
                }
                Button("Also Block…", systemImage: "plus") { composing = true }.linkStyle()
            }
            DisclosureGroup("Include My Rules", isExpanded: $includesRules) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    if rules.isEmpty {
                        Text("You haven’t saved any rules. Categories and apps work on their own.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(rules) { rule in
                        Toggle(rule.name, isOn: Binding(
                            get: { draft.ruleIDs.contains(rule.id) },
                            set: { enabled in
                                draft.ruleIDs.removeAll { $0 == rule.id }
                                if enabled { draft.ruleIDs.append(rule.id) }
                            })).toggleStyle(.checkbox)
                    }
                }.padding(.top, Theme.Space.s)
            }
            Toggle(isOn: $draft.isLocked) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Lock the session")
                    Text("No overrides and no ending early.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                }
            }.toggleStyle(.switch)
            automation
            HStack(spacing: Theme.Space.m) {
                Button("Start \(Format.minutesLabel(draft.minutes)) Focus") {
                    model.startFocus(profile: preparedDraft)
                }.buttonStyle(.borderedProminent).controlSize(.large)
                Button(profiles.contains { $0.id == draft.id } ? "Save Profile" : "Save as Profile") {
                    model.saveFocusProfile(preparedDraft)
                    Toast.show(title: "Profile Saved", detail: preparedDraft.name, symbol: "checkmark")
                }.buttonStyle(.bordered).controlSize(.large)
                Button("New Profile") {
                    load(FocusProfile(name: "Study"))
                }.linkStyle()
            }.disabled(!draft.hasSelection || requestingCalendar)
            Text("Save your profile to use its schedule, calendar trigger, and one-click start.")
                .font(Theme.Font.caption).foregroundStyle(.secondary)
        }
    }

    private var automation: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Toggle("Repeat on a schedule", isOn: Binding(
                get: { !draft.windows.isEmpty },
                set: { enabled in
                    draft.windows = enabled ? [ScheduleWindow(weekdays: ScheduleWindow.workdays,
                                                              startMinute: 9 * 60, endMinute: 10 * 60)] : []
                }))
            ForEach($draft.windows) { $window in
                ScheduleWindowEditor(window: $window, canRemove: true) {
                    draft.windows.removeAll { $0.id == window.id }
                }
            }
            if !draft.windows.isEmpty {
                Button("Add Time Window", systemImage: "plus") {
                    draft.windows.append(ScheduleWindow(weekdays: ScheduleWindow.workdays,
                                                         startMinute: 14 * 60, endMinute: 15 * 60))
                }.linkStyle()
            }
            Toggle("Start Focus during calendar events", isOn: Binding(
                get: { calendarEnabled },
                set: { enabled in
                    if !enabled { calendarEnabled = false; return }
                    requestingCalendar = true
                    Task {
                        calendarEnabled = await model.focusCalendar.requestAccess()
                        requestingCalendar = false
                    }
                })).disabled(requestingCalendar)
            if calendarEnabled {
                TextField("Event title contains, such as Writing", text: $calendarPhrase)
                    .textFieldStyle(.roundedBorder)
                Text("Only matching event titles and times are read. Focus ends when the event ends.")
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
            }
            if let message = model.focusCalendar.permissionMessage {
                Label(message, systemImage: "calendar.badge.exclamationmark")
                    .font(Theme.Font.caption).foregroundStyle(Theme.caution)
            }
        }
    }

    private var preparedDraft: FocusProfile {
        var profile = draft
        profile.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if profile.name.isEmpty { profile.name = "Focus" }
        let phrase = calendarPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.calendarTitleContains = calendarEnabled && !phrase.isEmpty ? phrase : nil
        return profile
    }

    private func load(_ profile: FocusProfile) {
        draft = profile
        calendarEnabled = profile.calendarTitleContains != nil
        calendarPhrase = profile.calendarTitleContains ?? ""
    }

    private func categoryBinding(_ category: UsageCategory) -> Binding<Bool> {
        Binding(get: { draft.categories.contains(category) }, set: { enabled in
            draft.categories.removeAll { $0 == category }
            if enabled { draft.categories.append(category) }
        })
    }
}

struct FocusProfilesView: View {
    let profiles: [FocusProfile]
    let defaultID: UUID?
    let start: (FocusProfile) -> Void
    let edit: (FocusProfile) -> Void
    let makeDefault: (FocusProfile) -> Void
    let delete: (FocusProfile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionTitle(title: "Your profiles")
            ForEach(profiles) { profile in
                HStack(spacing: Theme.Space.m) {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(profile.name).font(Theme.Font.heading)
                        Text("\(Format.minutesLabel(profile.minutes))\(profile.id == defaultID ? " · Default" : "")")
                            .font(Theme.Font.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Start") { start(profile) }.buttonStyle(.borderedProminent)
                    Menu {
                        Button("Edit Profile") { edit(profile) }
                        Button("Use by Default") { makeDefault(profile) }
                        Button("Delete Profile", role: .destructive) { delete(profile) }
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).fixedSize()
                        .accessibilityLabel("Options for \(profile.name)")
                }
            }
        }
    }
}

struct FocusRunningView: View {
    let focus: FocusSession
    let rules: [Rule]
    let extend: () -> Void
    let end: () -> Void

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                FocusArc(progress: 1 - focus.progress(at: timeline.date),
                         remaining: focus.end.timeIntervalSince(timeline.date))
            }.frame(width: 260, height: 260).frame(maxWidth: .infinity)
            VStack(spacing: Theme.Space.xs) {
                Text(focus.title).font(Theme.Font.title)
                Text("Until \(Format.clock(focus.end))\(focus.isLocked ? " · Locked" : "")")
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionTitle(title: "Blocking")
                ForEach(focus.categories ?? [], id: \.self) { category in
                    Label(category.title, systemImage: category.symbol)
                }
                ForEach(focus.targets ?? []) { target in
                    Label(target.displayName, systemImage: target.symbol)
                }
                ForEach(rules.filter { focus.ruleIDs.contains($0.id) }) { rule in
                    Label(rule.name, systemImage: rule.symbol)
                }
            }.frame(maxWidth: 360, alignment: .leading)
            Button("Extend 15 Min", action: extend).buttonStyle(.bordered).controlSize(.large)
            if focus.isLocked {
                Label("This session can’t be ended early.", systemImage: "lock.fill")
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
            } else {
                Button("End Focus", action: end).controlSize(.large)
            }
        }.frame(maxWidth: .infinity)
    }
}

/// Signature for Focus: one accent arc that drains as the session runs.
struct FocusArc: View {
    let progress: Double
    let remaining: TimeInterval
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, style: StrokeStyle(lineWidth: 10))
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 1), value: progress)
            VStack(spacing: 2) {
                Text(Format.countdown(remaining))
                    .font(Theme.Font.display(48))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                Text("remaining").font(Theme.Font.caption).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .accessibilityElement()
        .accessibilityLabel("Focus, \(Format.spokenDuration(remaining)) remaining")
    }
}
