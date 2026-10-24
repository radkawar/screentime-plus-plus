import ScreentimeCore
import SwiftUI

struct NotificationSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var requesting = false
    @State private var authorized = true

    var body: some View {
        Form {
            Section {
                Toggle("Time Nudges", isOn: Binding(
                    get: { model.configuration.settings.timeNudgesEnabled != false },
                    set: { enabled in model.updateSettings { $0.timeNudgesEnabled = enabled } }
                ))
                Picker("Remind After", selection: Binding(
                    get: { model.configuration.settings.timeNudgeCadence ?? .tenTwentyThirty },
                    set: { cadence in model.updateSettings { $0.timeNudgeCadence = cadence } }
                )) {
                    ForEach(TimeNudgeCadence.allCases, id: \.self) { cadence in
                        Text(cadence.title).tag(cadence)
                    }
                }
                .disabled(model.configuration.settings.timeNudgesEnabled == false)
                Toggle("Also for Everything", isOn: Binding(
                    get: { model.configuration.settings.timeNudgesForEverything == true },
                    set: { enabled in model.updateSettings { $0.timeNudgesForEverything = enabled } }
                ))
                .disabled(model.configuration.settings.timeNudgesEnabled == false)
            } header: {
                Text("In-App Nudges")
            } footer: {
                Text("Quiet reminders for continuous time on apps and sites covered by your rules, then every 30 minutes. Idle time resets the clock. Pause sessions also get a reminder with 2 minutes left. No sound or notification permission needed.")
            }
            Section {
                notificationToggle("Weekly Review Ready", detail: "Sunday at 18:00, in your local time.", keyPath: \.weeklyReviewNotifications)
                notificationToggle("Session Ending", detail: "A reminder 1 minute before a pause session ends.", keyPath: \.sessionEndingNotifications)
                notificationToggle("Daily Goal Reminder", detail: "Once a day when your distracting time reaches 80% of your goal.", keyPath: \.goalNotifications)
            } header: {
                Text("Notifications")
            } footer: {
                Text("System notifications are optional and off by default. Enabling one asks macOS for permission.")
            }
            if !authorized {
                Section {
                    Label("Allow notifications for Screentime++ in System Settings to receive reminders.", systemImage: "bell.slash")
                        .foregroundStyle(Theme.caution)
                    Button("Open Notification Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
            if let problem = model.notifications.problem {
                Text(problem).font(Theme.Font.caption).foregroundStyle(Theme.caution)
            }
        }
        .formStyle(.grouped)
        .tint(Theme.accent)
        .task { authorized = await model.notifications.isAuthorized() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    authorized = await model.notifications.isAuthorized()
                    model.notifications.reconcile(configuration: model.configuration, today: model.today)
                }
            }
        }
    }

    private func notificationToggle(_ title: String, detail: String, keyPath: WritableKeyPath<AppSettings, Bool?>) -> some View {
        Toggle(isOn: Binding(
            get: { model.configuration.settings[keyPath: keyPath] == true },
            set: { enabled in
                if !enabled {
                    model.updateSettings { $0[keyPath: keyPath] = false }
                    return
                }
                requesting = true
                Task { @MainActor in
                    authorized = await model.notifications.requestAuthorization()
                    if authorized { model.updateSettings { $0[keyPath: keyPath] = true } }
                    requesting = false
                }
            }
        )) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(title)
                Text(detail).font(Theme.Font.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(requesting)
    }
}
