import ScreentimeCore
import SwiftUI

struct RulesView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Rule?
    @State private var showsTemplates = false

    var body: some View {
        let rules = model.configuration.rules
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("\(rules.count) rules \u{00B7} \(rules.filter(\.isEnabled).count) on")
                        .font(Theme.Font.label)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.6)
                    Text("When several rules match, the strongest response wins.")
                        .font(Theme.Font.body)
                        .foregroundStyle(.secondary)
                }
                if model.rulesLocked, let until = model.configuration.settings.rulesLockedUntil {
                    HStack(alignment: .top, spacing: Theme.Space.m) {
                        Image(systemName: "lock.fill").foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Locked until \(until.formatted(date: .abbreviated, time: .shortened))")
                                .font(Theme.Font.body.weight(.medium))
                            Text("You can add rules, but not change, turn off or delete the ones you have.")
                                .font(Theme.Font.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(Theme.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
                }
                if rules.isEmpty {
                    ContentUnavailableView {
                        Label("No rules yet", systemImage: "hand.raised")
                    } description: {
                        Text("Rules decide what Screentime++ pauses, limits or blocks.")
                    } actions: {
                        Button("Browse the Library\u{2026}") { showsTemplates = true }.buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    VStack(spacing: 0) {
                        ForEach(rules) { rule in
                            RuleRow(rule: rule, usage: model.usage(for: rule), isEditable: model.canEdit(rule)) {
                                editing = rule
                            }
                            if rule.id != rules.last?.id { Divider().padding(.leading, 50) }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.l)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Rules")
        .toolbar {
            ToolbarItem {
                Button {
                    showsTemplates = true
                } label: {
                    Label("Add Rules", systemImage: "plus")
                }
                .help("Add rules from the Library")
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
                        .foregroundStyle(rule.isEnabled ? Theme.accent : .secondary)
                        .frame(width: 34, height: 34)
                        .background(
                            rule.isEnabled ? Theme.accentSoft : Theme.track,
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

/// The Library: curated packs added in one click, or a single rule to start
/// from. Vertical lists, not grids: each entry is a sentence.
struct TemplatePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    let choose: (RuleTemplate) -> Void

    enum Tab: String, CaseIterable, Identifiable {
        case packs = "Packs"
        case rules = "Single Rules"
        var id: String { rawValue }
    }

    @State private var tab: Tab

    init(initialTab: Tab = .packs, choose: @escaping (RuleTemplate) -> Void) {
        _tab = State(initialValue: initialTab)
        self.choose = choose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Library").font(Theme.Font.title)
                Spacer()
                Picker("Show", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            Text(
                tab == .packs
                    ? "Curated sets of rules. Add a pack, then make any rule your own."
                    : "Start one rule from a template. Everything stays editable."
            )
            .font(Theme.Font.body).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 0) {
                    switch tab {
                    case .packs:
                        ForEach(RulePack.all) { pack in
                            PackRow(pack: pack, isAdded: isAdded(pack)) { model.add(pack: pack) }
                            if pack.id != RulePack.all.last?.id { Divider().padding(.leading, 48) }
                        }
                    case .rules:
                        ForEach(RuleTemplate.all) { template in
                            templateRow(template)
                            if template.id != RuleTemplate.all.last?.id { Divider().padding(.leading, 48) }
                        }
                    }
                }
            }
            .frame(height: 430)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(Theme.Space.l)
        .frame(width: 540)
    }

    private func isAdded(_ pack: RulePack) -> Bool {
        let names = Set(model.configuration.rules.map(\.name))
        return pack.templates.allSatisfy { names.contains($0.make().name) }
    }

    private func templateRow(_ template: RuleTemplate) -> some View {
        Button {
            choose(template)
        } label: {
            HStack(spacing: Theme.Space.m) {
                LibrarySymbol(symbol: template.symbol)
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
    }
}

private struct PackRow: View {
    let pack: RulePack
    let isAdded: Bool
    let add: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            LibrarySymbol(symbol: pack.symbol)
            VStack(alignment: .leading, spacing: 4) {
                Text(pack.title).font(Theme.Font.body.weight(.semibold))
                Text(pack.subtitle).font(Theme.Font.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                FlowLayout(spacing: 6) {
                    ForEach(pack.templates) { template in
                        Chip(title: template.title, symbol: template.symbol)
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: Theme.Space.m)
            if isAdded {
                Label("Added", systemImage: "checkmark")
                    .font(Theme.Font.label)
                    .foregroundStyle(Theme.accent)
                    .frame(minWidth: 64)
            } else {
                Button("Add", action: add)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .frame(minWidth: 64)
            }
        }
        .padding(.vertical, 10)
    }
}

private struct LibrarySymbol: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15))
            .foregroundStyle(Theme.accent)
            .frame(width: 32, height: 32)
            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
