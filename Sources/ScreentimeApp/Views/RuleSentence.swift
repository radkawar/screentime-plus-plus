import ScreentimeCore
import SwiftUI

/// The common edits stay in the sentence; precise settings remain in Details.
struct RuleSentenceEditor: View {
    @Binding var rule: Rule
    @Binding var showsDetails: Bool
    let addTarget: () -> Void
    let addException: () -> Void

    var body: some View {
        let sentence = RuleSentence(rule: rule)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            FlowLayout(spacing: Theme.Space.xs, lineSpacing: Theme.Space.s) {
                Text("When you open")
                token(sentence.subject, label: "Edit Apps, Sites or Content") {
                    Button("Choose App, Site, Page or Phrase…", action: addTarget)
                    Menu("Use a Category") {
                        ForEach(UsageCategory.allCases) { category in
                            Button(category.title) { rule.targets = [.category(category)] }
                        }
                    }
                    if !rule.targets.isEmpty {
                        Menu("Remove a Target") {
                            ForEach(rule.targets) { target in
                                Button(target.displayName) { rule.targets.removeAll { $0 == target } }
                            }
                        }
                    }
                }
                if let exceptions = sentence.exceptions {
                    token(", " + exceptions + ",", label: "Edit Exceptions") {
                        Button("Add Exception…", action: addException)
                        ForEach(rule.exceptions) { target in
                            Button("Remove \(target.displayName)") { rule.exceptions.removeAll { $0 == target } }
                        }
                    }
                }
                token(sentence.schedule + ",", label: "Edit Schedule") {
                    Button("Any Time") { rule.schedule = .always }
                    Button("During Focus") { rule.schedule = .duringFocus }
                    Button("Weekdays, 9 AM–5 PM") {
                        rule.schedule = .windows([ScheduleWindow(weekdays: ScheduleWindow.workdays, startMinute: 540, endMinute: 1020)])
                    }
                    Button("Every Night, 10 PM–7 AM") {
                        rule.schedule = .windows([ScheduleWindow(weekdays: ScheduleWindow.everyDay, startMinute: 1320, endMinute: 420)])
                    }
                    Button("Custom Schedule…") {
                        if case .windows = rule.schedule {} else {
                            rule.schedule = .windows([ScheduleWindow(weekdays: ScheduleWindow.everyDay, startMinute: 540, endMinute: 1020)])
                        }
                        showsDetails = true
                    }
                }
                token(sentence.response, label: "Edit Response") {
                    Button("Track Your Time") { rule.response = .track }
                    ForEach([5, 10, 20, 30], id: \.self) { seconds in
                        Button("Pause \(seconds)s, Longer Each Open") {
                            rule.response = .pause(PauseSettings(waitSeconds: seconds))
                        }
                        Button("Pause \(seconds)s Each Open") {
                            rule.response = .pause(PauseSettings(waitSeconds: seconds, escalationSeconds: 0))
                        }
                    }
                    Divider()
                    Button("Block, Allow a One-Minute Override") { rule.response = .block(BlockSettings()) }
                    Button("Block Without Overrides") { rule.response = .block(BlockSettings(allowsOverride: false)) }
                    Button("More Response Settings…") { showsDetails = true }
                }
                if sentence.limits != nil { Text("and") }
                token(sentence.limits ?? "with no daily limit", label: "Edit Daily Limits") {
                    Button("No Daily Limit") { rule.limits = UsageLimits() }
                    Menu("Daily Time") {
                        Button("No Time Limit") { rule.limits.dailyMinutes = nil }
                        ForEach([15, 30, 45, 60, 90, 120], id: \.self) { minutes in
                            Button("\(minutes) Minutes") { rule.limits.dailyMinutes = minutes }
                        }
                    }
                    Menu("Daily Opens") {
                        Button("No Open Limit") { rule.limits.dailyOpens = nil }
                        ForEach([1, 5, 10, 15, 20], id: \.self) { opens in
                            Button("\(opens) Open\(opens == 1 ? "" : "s")") { rule.limits.dailyOpens = opens }
                        }
                    }
                    Button("Custom Limits…") { showsDetails = true }
                }
                Text(".")
            }
            .font(.system(size: 20, design: .serif))
            if rule.exceptions.isEmpty {
                Button("Add Exception…", action: addException)
                    .linkStyle()
                    .font(Theme.Font.caption)
            }
            Text("Choose a highlighted phrase to change it.")
                .font(Theme.Font.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, Theme.Space.s)
    }

    private func token<Content: View>(_ title: String, label: String, @ViewBuilder content: () -> Content) -> some View {
        Menu(content: content) {
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, Theme.Space.xs)
                .padding(.vertical, Theme.Space.xs)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        // Highlighted phrases are the sentence's controls: keep them in the accent.
        .tint(Theme.accent)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(label)
        .accessibilityValue(title)
    }
}
