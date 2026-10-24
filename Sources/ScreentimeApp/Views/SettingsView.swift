import ScreentimeCore
import Sparkle
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let updater: SPUUpdater
    @State private var tab: SettingsTab = .general
    @State private var search = ""

    init(updater: SPUUpdater, initialSearch: String = "") {
        self.updater = updater
        _search = State(initialValue: initialSearch)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search Settings", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .accessibilityLabel("Clear Search")
                }
            }
            .padding(Theme.Space.s)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
            .padding([.horizontal, .top], Theme.Space.m)
            Picker("Settings", selection: $tab) {
                ForEach(SettingsTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(Theme.Space.m)
            if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                switch tab {
                case .general: GeneralSettings()
                case .shields: ShieldSettings()
                case .lock: LockSettings()
                case .privacy: PrivacySettings()
                case .notifications: NotificationSettings().fixedSize(horizontal: false, vertical: true)
                case .updates: UpdateSettings(updater: updater)
                }
            } else {
                searchResults
            }
        }
        .frame(width: 620)
        .fixedSize(horizontal: false, vertical: true)
        .tint(Theme.accent)
    }

    private var searchResults: some View {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let results = SettingsTab.allCases.flatMap { tab in
            tab.rows.filter { $0.localizedCaseInsensitiveContains(query) || tab.rawValue.localizedCaseInsensitiveContains(query) }
                .map { (tab, $0) }
        }
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            if results.isEmpty {
                Text("No settings match “\(query)”.").foregroundStyle(.secondary)
                    .padding(.vertical, Theme.Space.m)
            } else {
                ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                    Button {
                        tab = result.0
                        search = ""
                    } label: {
                        HStack {
                            Text(result.1)
                            Spacer()
                            Text(result.0.rawValue).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, Theme.Space.s)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding([.horizontal, .bottom], Theme.Space.m)
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General", shields = "Shields", lock = "Lock"
    case privacy = "Privacy & Data", notifications = "Notifications", updates = "Updates"
    var id: String { rawValue }

    var rows: [String] {
        switch self {
        case .general: ["Open at Login", "Distracting Time per Day", "Stop the Clock After", "Per-App Idle Overrides"]
        case .shields: ["Read Page Text for Phrase Rules", "Blank the Tab Behind a Shield", "Accessibility", "Automation Settings"]
        case .lock: ["Lock Rules", "Extend Lock"]
        case .privacy: ["Keep History For", "Export History CSV", "Delete All History", "Import Screen Time"]
        case .notifications: ["Weekly Review Ready", "Session Ending", "Daily Goal Reminder"]
        case .updates: ["Check for Updates Automatically", "Check Now", "Version"]
        }
    }
}

struct GeneralSettings: View {
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
            IdleSettings()
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { launchesAtLogin = model.launchesAtLogin }
    }
}

struct ShieldSettings: View {
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
                        Label("On", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                    } else {
                        Button("Turn On\u{2026}") { model.requestAccessibility() }
                    }
                }
                Button("Open Automation Settings\u{2026}") {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                }
                .buttonStyle(.borderless)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct LockSettings: View {
    @Environment(AppModel.self) private var model
    @State private var duration: Duration = .hour
    @State private var confirms = false

    enum Duration: String, CaseIterable, Identifiable {
        case hour = "For 1 hour"
        case morning = "Until tomorrow morning"
        case week = "For a week"
        var id: String { rawValue }

        var end: Date {
            switch self {
            case .hour: return Date().addingTimeInterval(3_600)
            case .week: return Date().addingTimeInterval(7 * 86_400)
            case .morning:
                let calendar = Calendar.current
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
                return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow)!
            }
        }
    }

    var body: some View {
        Form {
            Section {
                if let until = model.configuration.settings.rulesLockedUntil, model.rulesLocked {
                    Label(
                        "Locked until \(until.formatted(date: .abbreviated, time: .shortened))", systemImage: "lock.fill"
                    )
                    .foregroundStyle(Theme.accent)
                }
                Text(
                    "Locking stops you from weakening your rules in a weak moment. Existing rules can\u{2019}t be edited, turned off or deleted until the lock ends. You can still add rules, and extend a lock."
                )
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
            }
            Section {
                Picker("Lock rules", selection: $duration) {
                    ForEach(Duration.allCases) { Text($0.rawValue).tag($0) }
                }
                HStack {
                    Spacer()
                    Button(model.rulesLocked ? "Extend Lock\u{2026}" : "Lock Rules\u{2026}") { confirms = true }
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("Lock your rules?", isPresented: $confirms) {
            Button("Lock") { model.lockRules(until: duration.end) }
        } message: {
            Text("Until \(duration.end.formatted(date: .abbreviated, time: .shortened)) there is no way to unlock early.")
        }
    }
}

struct PrivacySettings: View {
    @Environment(AppModel.self) private var model
    @State private var confirmsDelete = false

    @State private var exportDays = 7
    @State private var exporting = false
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
                    .foregroundStyle(.red)
            }
            Section("Export") {
                Picker("Export history", selection: $exportDays) {
                    Text("Last 7 days").tag(7)
                    Text("Last 30 days").tag(30)
                    Text("All history").tag(0)
                }
                Button(exporting ? "Exporting…" : "Export CSV…") { exportHistory() }
                    .disabled(exporting)
                Text("Your CSV includes time, apps, domains, surfaces, categories and matched rules.")
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
            }
            ScreenTimeImportSettings()
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("Delete all history?", isPresented: $confirmsDelete) {
            Button("Delete History", role: .destructive) { model.deleteHistory() }
        } message: {
            Text("Recorded time, interventions and streaks are removed. Rules and settings are kept.")
        }
    }

    private func exportHistory() {
        guard let store = model.store else {
            RulePackFiles.showError(CocoaError(.fileReadUnknown))
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Screentime History.csv"
        panel.prompt = "Export"
        let days = exportDays
        let names = Dictionary(model.configuration.rules.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.flush()
            exporting = true
            Task {
                do {
                    try await Task.detached(priority: .userInitiated) {
                        let now = Date()
                        let start = days == 0 ? Date.distantPast
                            : Calendar.current.date(byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: now))!
                        let segments = try store.segments(in: DateInterval(start: start, end: now))
                        try HistoryCSV.encode(segments, ruleNames: names).write(to: url, atomically: true, encoding: .utf8)
                    }.value
                } catch {
                    RulePackFiles.showError(error)
                }
                exporting = false
            }
        }
    }
}

struct UpdateSettings: View {
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
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { automatic = updater.automaticallyChecksForUpdates }
    }
}
