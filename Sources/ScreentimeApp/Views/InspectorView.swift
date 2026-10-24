import ScreentimeCore
import SwiftUI

/// What the engine sees right now, and what each rule thinks of it.
/// Deep inspection is only trustworthy if it is visible.
struct InspectorView: View {
    @Environment(AppModel.self) private var model
    @State private var showsText = false

    var body: some View {
        let live = model.live
        Form {
            Section("In front") {
                if let context = live.context {
                    LabeledContent("App") {
                        HStack(spacing: 6) {
                            SubjectIcon(bundleID: context.bundleID, size: 16)
                            Text(context.appName)
                        }
                    }
                    if let url = context.url {
                        LabeledContent("Address") {
                            Text(url.absoluteString).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                        }
                    } else if context.isBrowser {
                        LabeledContent("Address", value: "No web page read")
                    }
                    if let title = context.pageTitle ?? context.windowTitle {
                        LabeledContent("Title") { Text(title).lineLimit(2) }
                    }
                    LabeledContent("Category", value: context.category.title)
                    if let surface = context.surface { LabeledContent("Surface", value: surface) }
                }
                LabeledContent("Status", value: statusText(live.status))
            }

            Section {
                if let content = live.content {
                    LabeledContent("Read", value: "\(content.characterCount.formatted()) characters from \(content.nodeCount.formatted()) elements")
                    LabeledContent("Complete", value: content.isPartial ? "Partial (budget reached)" : "Yes")
                    LabeledContent("Age", value: "\(max(0, Int(model.now.timeIntervalSince(content.capturedAt))))s")
                    Toggle("Show text", isOn: $showsText)
                    if showsText {
                        Text(String(content.text.value.prefix(1_500)))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text("No page text read yet. It\u{2019}s read while this pane is open and when a rule needs it.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Page text")
            } footer: {
                Text("Folded to lowercase without accents for matching. Never saved.")
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
            }

            Section("Rules") {
                if model.configuration.rules.isEmpty {
                    Text("No rules.").foregroundStyle(.secondary)
                }
                ForEach(model.configuration.rules) { rule in
                    RuleVerdictRow(rule: rule, live: live)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Inspector")
        .onAppear { model.isInspectorOpen = true }
        .onDisappear { model.isInspectorOpen = false }
    }

    private func statusText(_ status: LiveState.Status) -> String {
        switch status {
        case .starting: "Starting"
        case .active: "Watching"
        case .idle: "Idle, clock stopped"
        case .away: "Screen locked or asleep"
        case .own: "Screentime++ is in front"
        case .needsAccessibility: "Needs Accessibility access"
        }
    }
}

private struct RuleVerdictRow: View {
    let rule: Rule
    let live: LiveState

    var body: some View {
        let match = live.evaluation.matches.first { $0.rule.id == rule.id }
        let intervention = live.evaluation.intervention
        let isActing = intervention?.match.rule.id == rule.id
        HStack(spacing: Theme.Space.s) {
            Image(systemName: rule.symbol).foregroundStyle(match == nil ? Color.secondary : Theme.accent).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                if let match {
                    Text("Matched \(match.target.kindName.lowercased()): \(match.evidence.summary)")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                } else {
                    Text(rule.isEnabled ? "No match" : "Off").font(Theme.Font.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if isActing, let intervention {
                Text(verdict(intervention))
                    .font(Theme.Font.label)
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.accentSoft, in: Capsule())
            } else if match != nil {
                Text("Allowed").font(Theme.Font.label).foregroundStyle(.secondary)
            }
        }
    }

    private func verdict(_ intervention: Intervention) -> String {
        switch intervention {
        case .pause(let pause): "Pause \(pause.waitSeconds)s"
        case .block: "Block"
        }
    }
}
