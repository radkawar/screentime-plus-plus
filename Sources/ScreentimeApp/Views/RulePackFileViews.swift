import AppKit
import ScreentimeCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let screentimeRulePack = UTType(exportedAs: "dev.screentimepp.rulepack", conformingTo: .json)
}

@MainActor
enum RulePackFiles {
    private static var importWindows: [NSWindow] = []

    static func chooseImport(model: AppModel) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.screentimeRulePack]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Preview"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            open(url, model: model)
        }
    }

    static func open(_ url: URL, model: AppModel) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let rules = try RulePackCodec.decode(Data(contentsOf: url))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Import Rule Pack"
            window.isReleasedWhenClosed = false
            let view = RulePackImportPreview(rules: rules) { [weak window] in window?.close() }
                .environment(model)
            let host = NSHostingView(rootView: view)
            host.sizingOptions = []
            window.contentView = host
            importWindows.removeAll { !$0.isVisible }
            importWindows.append(window)
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            showError(error)
        }
    }

    static func export(_ rules: [Rule], completion: @escaping () -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.screentimeRulePack]
        panel.nameFieldStringValue = "Rules.stpack"
        panel.prompt = "Export"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try RulePackCodec.encode(rules).write(to: url, options: .atomic)
                completion()
            } catch { showError(error) }
        }
    }

    static func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}

struct RulePackImportPreview: View {
    @Environment(AppModel.self) private var model
    let rules: [Rule]
    var close: () -> Void = {}

    private var existingNames: Set<String> { Set(model.configuration.rules.map(\.name)) }
    private var additions: [Rule] {
        var names = existingNames
        return rules.filter { names.insert($0.name).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Import Rule Pack").font(Theme.Font.title)
            Text("Add \(additions.count) of \(rules.count) rules. Names you already have are skipped.")
                .font(Theme.Font.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.rulesLocked {
                Label("Your existing rules stay locked. You can still add rules.", systemImage: "lock.fill")
                    .font(Theme.Font.caption).foregroundStyle(Theme.accent)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                        HStack(spacing: Theme.Space.m) {
                            Image(systemName: rule.symbol).foregroundStyle(Theme.accent).frame(width: 24)
                            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                Text(rule.name).font(Theme.Font.body.weight(.semibold))
                                Text(rule.targetSummary).font(Theme.Font.caption).foregroundStyle(.secondary)
                                Text(rule.summary).font(Theme.Font.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if existingNames.contains(rule.name) || rules.prefix(index).contains(where: { $0.name == rule.name }) {
                                Text("Skipped").font(Theme.Font.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                Button("Add") {
                    for rule in RulePackCodec.rulesToAdd(rules, existingNames: existingNames) { model.save(rule: rule) }
                    close()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(additions.isEmpty)
            }
        }
        .padding(Theme.Space.l)
        .frame(minWidth: 472, minHeight: 392)
    }
}

struct RulePackExportPicker: View {
    @Environment(\.dismiss) private var dismiss
    let rules: [Rule]
    @State private var selected: Set<UUID>

    init(rules: [Rule]) {
        self.rules = rules
        _selected = State(initialValue: Set(rules.map(\.id)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Export Rules").font(Theme.Font.title)
            Text("Choose rules to share or keep as a backup. History and settings are not included.")
                .font(Theme.Font.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Select All") { selected = Set(rules.map(\.id)) }
                Button("Deselect All") { selected.removeAll() }
            }.linkStyle()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    ForEach(rules) { rule in
                        Toggle(rule.name, isOn: Binding(
                            get: { selected.contains(rule.id) },
                            set: { if $0 { selected.insert(rule.id) } else { selected.remove(rule.id) } }))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 240)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Export…") { RulePackFiles.export(rules.filter { selected.contains($0.id) }) { dismiss() } }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(selected.isEmpty)
            }
        }.padding(Theme.Space.l).frame(width: 480)
    }
}
