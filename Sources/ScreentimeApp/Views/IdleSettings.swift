import ScreentimeCore
import SwiftUI

/// A section hosted by the General settings form.
struct IdleSettings: View {
    @Environment(AppModel.self) private var model
    @State private var apps: [InstalledApp] = []
    @State private var selectedBundleID = ""

    private var overrides: [String: AppIdleOverride] { model.configuration.settings.appIdleOverrides ?? [:] }

    var body: some View {
        Section("Idle") {
            Picker("Stop the clock after", selection: Binding(
                get: { model.configuration.settings.idleThresholdSeconds },
                set: { value in model.updateSettings { $0.idleThresholdSeconds = value } }
            )) {
                Text("1 minute").tag(60)
                Text("2 minutes").tag(120)
                Text("5 minutes").tag(300)
                Text("10 minutes").tag(600)
            }
            Text("Video that keeps your display awake still counts as use, unless you set an app timeout below.")
                .font(Theme.Font.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(overrides.keys.sorted(), id: \.self) { bundleID in
                overrideRow(bundleID)
            }
            HStack {
                Picker("App", selection: $selectedBundleID) {
                    Text("Choose an App").tag("")
                    ForEach(apps.filter { overrides[$0.bundleID] == nil }) { app in
                        Text(app.name).tag(app.bundleID)
                    }
                }
                Button("Add App") {
                    set(.alwaysCountsAsUse, for: selectedBundleID)
                    selectedBundleID = ""
                }
                .disabled(selectedBundleID.isEmpty)
            }
            Text("App settings replace the global timeout. They apply only while that app is frontmost and your Mac is awake and unlocked.")
                .font(Theme.Font.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task { apps = await AppCatalog.installed() }
    }

    private func overrideRow(_ bundleID: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                SubjectIcon(bundleID: bundleID, size: 20)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(apps.first { $0.bundleID == bundleID }?.name ?? bundleID)
                    Text(bundleID).font(Theme.Font.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Remove", role: .destructive) { set(nil, for: bundleID) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Remove idle setting for \(bundleID)")
            }
            Picker("When you stop input", selection: Binding(
                get: { overrides[bundleID] == .alwaysCountsAsUse },
                set: { set($0 ? .alwaysCountsAsUse : .idleAfter(minutes: 2), for: bundleID) }
            )) {
                Text("Always counts as use").tag(true)
                Text("Idle after a timeout").tag(false)
            }
            if case .idleAfter(let minutes) = overrides[bundleID] {
                Stepper(value: Binding(
                    get: { minutes },
                    set: { set(.idleAfter(minutes: $0), for: bundleID) }
                ), in: 1...120) {
                    Text("Idle after \(minutes) minute\(minutes == 1 ? "" : "s")").monospacedDigit()
                }
                Text("Stops counting even if an app keeps your display awake.")
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func set(_ policy: AppIdleOverride?, for bundleID: String) {
        model.updateSettings {
            var values = $0.appIdleOverrides ?? [:]
            values[bundleID] = policy
            $0.appIdleOverrides = values.isEmpty ? nil : values
        }
    }
}
