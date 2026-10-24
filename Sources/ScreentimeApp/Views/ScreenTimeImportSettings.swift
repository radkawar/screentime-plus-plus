import ScreentimeCore
import SwiftUI

/// A section hosted by Privacy settings. Import never runs without a deliberate confirmation.
struct ScreenTimeImportSettings: View {
    @Environment(AppModel.self) private var model
    @State private var isImporting = false
    @State private var hasImported = false
    @State private var confirmsImport = false
    @State private var result: String?
    @State private var failed = false

    var body: some View {
        Section("Import Mac App History") {
            Text("You can import the app history still stored on this Mac once. It may be incomplete or end days ago, and may differ from Screen Time totals.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Only time before your existing recordings is added, within your history retention period. Websites and distracting time are not imported. Deleting history does not reset the import.")
                .font(Theme.Font.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("If access is denied, add Screentime++ in System Settings → Privacy & Security → Full Disk Access, then quit and reopen the app. You can remove that permission after importing.")
                .font(Theme.Font.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Full Disk Access Settings…") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
            .buttonStyle(.borderless)
            if hasImported {
                Label("App history has been imported", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
            } else {
                HStack {
                    Button("Import App History…") { confirmsImport = true }
                        .disabled(isImporting || model.store == nil)
                    if isImporting { ProgressView().controlSize(.small) }
                }
            }
            if let result {
                Label(result, systemImage: failed ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(Theme.Font.caption)
                    .foregroundStyle(failed ? Theme.caution : Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .task {
            do { hasImported = try model.store?.hasImportedScreenTime() ?? false }
            catch { failed = true; result = error.localizedDescription }
        }
        .confirmationDialog("Import available app history once?", isPresented: $confirmsImport) {
            Button("Import App History") { beginImport() }
        } message: {
            Text("This adds the available local history, even if macOS has kept only part of it. You cannot run the import again, including after deleting history.")
        }
    }

    private func beginImport() {
        guard let store = model.store, !isImporting else { return }
        isImporting = true
        result = nil
        let since = Date().addingTimeInterval(-TimeInterval(model.configuration.settings.retentionDays) * 86_400)
        Task {
            do {
                let count = try await Task.detached(priority: .userInitiated) {
                    try ScreenTimeImporter.run(into: store, since: since)
                }.value
                hasImported = true
                failed = false
                result = "Imported \(count.formatted()) app usage intervals."
                model.refreshNow()
            } catch {
                failed = true
                result = error.localizedDescription
            }
            isImporting = false
        }
    }
}
