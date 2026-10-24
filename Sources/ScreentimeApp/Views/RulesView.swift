import ScreentimeCore
import SwiftUI

struct RulesView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Rule?
    @State private var showsTemplates = false

    var body: some View {
        let rules = model.configuration.rules
        List {
            if model.rulesLocked, let until = model.configuration.settings.rulesLockedUntil {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Rules are locked until \(until.formatted(date: .abbreviated, time: .shortened))")
                                .font(Theme.Font.body.weight(.medium))
                            Text("You can add rules, but not change, turn off or delete the ones you have.")
                                .font(Theme.Font.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "lock.fill").foregroundStyle(Theme.ember)
                    }
                }
            }
            Section {
                ForEach(rules) { rule in
                    RuleRow(rule: rule, usage: model.usage(for: rule), isEditable: model.canEdit(rule)) {
                        editing = rule
                    }
                }
                .onMove { model.moveRules(from: $0, to: $1) }
            } header: {
                Text("Rules apply from the top. When several match, the strongest response wins.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: false))
        .overlay {
            if rules.isEmpty {
                ContentUnavailableView {
                    Label("No rules yet", systemImage: "hand.raised")
                } description: {
                    Text("Rules decide what Screentime++ pauses, limits or blocks.")
                } actions: {
                    Button("New Rule\u{2026}") { showsTemplates = true }.buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Rules")
        .toolbar {
            ToolbarItem {
                Button {
                    showsTemplates = true
                } label: {
                    Label("New Rule", systemImage: "plus")
                }
                .help("New rule")
            }
        }
        .sheet(isPresented: $showsTemplates) {
            TemplatePicker { template in
                showsTemplates = false
                editing = template.make()
            }
        }
        .sheet(item: $editing) { rule in
            RuleEditor(rule: rule, isNew: !rules.contains { $0.id == rule.id })
        }
    }
}

private struct RuleRow: View {
    @Environment(AppModel.self) private var model
    let rule: Rule
    let usage: RuleDayUsage
    let isEditable: Bool
    let open: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Button(action: open) {
                HStack(spacing: Theme.Space.m) {
                    Image(systemName: rule.symbol)
                        .font(.system(size: 15))
                        .foregroundStyle(rule.isEnabled ? Theme.ember : .secondary)
                        .frame(width: 34, height: 34)
                        .background(
                            rule.isEnabled ? Theme.emberSoft : Theme.track,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: Theme.Space.s) {
                            Text(rule.name).font(Theme.Font.body.weight(.semibold))
                            if !isEditable {
                                Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }
                        Text(rule.targetSummary).font(Theme.Font.caption).lineLimit(1)
                        Text(rule.summary).font(Theme.Font.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: Theme.Space.m)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(Format.duration(usage.seconds)).font(Theme.Font.body).monospacedDigit()
                        Text("\(usage.opens) open\(usage.opens == 1 ? "" : "s") today")
                            .font(Theme.Font.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit \(rule.name)")
            Toggle(
                "Enabled",
                isOn: Binding(get: { rule.isEnabled }, set: { model.setEnabled($0, rule: rule) })
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .disabled(!isEditable)
            .help(isEditable ? "Turn this rule on or off" : "Locked")
        }
        .padding(.vertical, 6)
        .contextMenu {
            Button("Edit\u{2026}", action: open)
            Divider()
            Button("Delete", role: .destructive) { model.delete(rule: rule) }.disabled(!isEditable)
        }
    }
}

/// Starting points. A vertical list, not a grid: each template is a sentence.
struct TemplatePicker: View {
    @Environment(\.dismiss) private var dismiss
    let choose: (RuleTemplate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("New Rule").font(Theme.Font.title)
            Text("Start from a template. Everything stays editable.")
                .font(Theme.Font.body).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(RuleTemplate.all) { template in
                    Button {
                        choose(template)
                    } label: {
                        HStack(spacing: Theme.Space.m) {
                            Image(systemName: template.symbol)
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.ember)
                                .frame(width: 32, height: 32)
                                .background(Theme.emberSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.title).font(Theme.Font.body.weight(.semibold))
                                Text(template.subtitle).font(Theme.Font.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if template.id != RuleTemplate.all.last?.id { Divider().padding(.leading, 48) }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(Theme.Space.l)
        .frame(width: 480)
    }
}
