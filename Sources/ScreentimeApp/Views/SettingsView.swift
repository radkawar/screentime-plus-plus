import ScreentimeCore
import Sparkle
import SwiftUI

struct SettingsView: View {
    let updater: SPUUpdater

    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            ShieldSettings().tabItem { Label("Shields", systemImage: "hand.raised") }
            LockSettings().tabItem { Label("Lock", systemImage: "lock") }
            PrivacySettings().tabItem { Label("Privacy", systemImage: "hand.raised.square") }
            UpdateSettings(updater: updater).tabItem { Label("Updates", systemImage: "arrow.down.circle") }
        }
        .frame(width: 520)
        .tint(Theme.ember)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var launchesAtLogin = false

    var body: some View {
        let settings = model.configuration.settings
        Form {
            Section {
                Toggle("Open at login", isOn: $launchesAtLogin)
                    .onChange(of: launchesAtLogin) { _, value in model.launchesAtLogin = value }
            } footer: {
                Text("Rules only work while Screentime++ is running.").font(Theme.Font.caption).foregroundStyle(.secondary)
            }
            Section("Goal") {
                Stepper(
                    value: Binding(
                        get: { settings.dailyGoalMinutes },
                        set: { value in model.updateSettings { $0.dailyGoalMinutes = value } }),
                    in: 10...600, step: 10
                ) {
                    LabeledContent("Distracting time per day", value: Format.duration(TimeInterval(settings.dailyGoalMinutes * 60)))
                }
                Text("Distracting time is time spent on anything a rule covers.")
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
            }
            Section("Idle") {
                Picker(
                    "Stop the clock after",
                    selection: Binding(
                        get: { settings.idleThresholdSeconds },
                        set: { value in model.updateSettings { $0.idleThresholdSeconds = value } })
                ) {
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                    Text("5 minutes").tag(300)
                    Text("10 minutes").tag(600)
                }
                Text("Video that keeps the display awake still counts as use.")
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { launchesAtLogin = model.launchesAtLogin }
    }
}

private struct ShieldSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let settings = model.configuration.settings
        Form {
            Section {
                Toggle(
                    "Read page text for phrase rules",
                    isOn: Binding(
                        get: { settings.inspectsPageText },
                        set: { value in model.updateSettings { $0.inspectsPageText = value } }))
                Text("Off means phrase rules only see the page title and address.")
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle(
                    "Blank the tab behind a shield",
                    isOn: Binding(
                        get: { settings.parksBrowserTabs },
                        set: { value in model.updateSettings { $0.parksBrowserTabs = value } }))
                Text(
                    "In Safari, Chrome, Arc, Brave, Edge and Vivaldi the tab is replaced with a blank page so audio and video stop, and restored if you continue. macOS asks once per browser."
                )
                .font(Theme.Font.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Section("Permissions") {
                LabeledContent("Accessibility") {
                    if model.isAccessibilityTrusted {
                        Label("On", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.color(for: .productivity))
                    } else {
                        Button("Turn On\u{2026}") { model.requestAccessibility() }
                    }
                }
                Button("Open Automation Settings\u{2026}") {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                }
                .buttonStyle(.link)
            }
        }
        .formStyle(.grouped)
    }
}

private struct LockSettings: View {
    @Environment(AppModel.self) private var model
    @State private var confirming: Date?

    var body: some View {
        Form {
            Section {
                if let until = model.configuration.settings.rulesLockedUntil, model.rulesLocked {
                    Label(
                        "Locked until \(until.formatted(date: .abbreviated, time: .shortened))", systemImage: "lock.fill"
                    )
                    .foregroundStyle(Theme.ember)
                    Text("You can still add rules. You can extend the lock, but not shorten it.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                } else {
                    Text("Locking stops you from weakening your rules in a weak moment. Existing rules can\u{2019}t be edited, turned off or deleted until the lock ends.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section("Lock rules") {
                lockButton("For 1 hour", Date().addingTimeInterval(3_600))
                lockButton("Until tomorrow morning", Self.tomorrowMorning())
                lockButton("For a week", Date().addingTimeInterval(7 * 86_400))
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Lock your rules?", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })
        ) {
            Button("Lock") {
                if let date = confirming { model.lockRules(until: date) }
                confirming = nil
            }
        } message: {
            if let date = confirming {
                Text("Until \(date.formatted(date: .abbreviated, time: .shortened)) there is no way to unlock early.")
            }
        }
    }

    private func lockButton(_ title: String, _ until: Date) -> some View {
        Button(title) { confirming = until }
    }

    private static func tomorrowMorning() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow)!
    }
}

private struct PrivacySettings: View {
    @Environment(AppModel.self) private var model
    @State private var confirmsDelete = false

    var body: some View {
        Form {
            Section {
                Text(
                    "Everything stays on this Mac. History keeps time, app identifiers, website hosts and page surfaces such as \u{201C}Shorts\u{201D}. It never keeps full addresses, titles, or page text."
                )
                .fixedSize(horizontal: false, vertical: true)
            }
            Section("History") {
                Picker(
                    "Keep history for",
                    selection: Binding(
                        get: { model.configuration.settings.retentionDays },
                        set: { value in model.updateSettings { $0.retentionDays = value } })
                ) {
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("6 months").tag(180)
                    Text("1 year").tag(365)
                }
                Button("Delete All History\u{2026}", role: .destructive) { confirmsDelete = true }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete all history?", isPresented: $confirmsDelete) {
            Button("Delete History", role: .destructive) { model.deleteHistory() }
        } message: {
            Text("Recorded time, interventions and streaks are removed. Rules and settings are kept.")
        }
    }
}

private struct UpdateSettings: View {
    let updater: SPUUpdater
    @State private var automatic = false

    var body: some View {
        Form {
            Section {
                Toggle("Check for updates automatically", isOn: $automatic)
                    .onChange(of: automatic) { _, value in updater.automaticallyChecksForUpdates = value }
                Button("Check Now") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            } footer: {
                Text(
                    "Updates are signed by Apple Developer ID and by Screentime++\u{2019}s own update key, and installed only after you approve them."
                )
                .font(Theme.Font.caption)
                .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent(
                    "Version",
                    value:
                        "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))"
                )
            }
        }
        .formStyle(.grouped)
        .onAppear { automatic = updater.automaticallyChecksForUpdates }
    }
}
