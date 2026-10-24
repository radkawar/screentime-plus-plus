import ScreentimeCore
import SwiftUI

struct RulesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @State private var editing: Rule?
    @State private var showsTemplates = false
    @State private var showsExport = false
    @State private var lockDuration = LockSettings.Duration.hour
    @State private var confirmsLock = false

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
                        Label("Make room for what you came to do", systemImage: "leaf")
                    } description: {
                        Text("Choose an app or site. Add a pause before opening it, a daily limit, or a block.")
                    } actions: {
                        Button("Create a Rule") { editing = RuleTemplate.blank.make() }
                            .buttonStyle(.borderedProminent)
                        Button("Browse the Library…") { showsTemplates = true }.buttonStyle(.borderless)
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
                Menu {
                    ForEach(LockSettings.Duration.allCases) { duration in
                        Button(duration.rawValue) {
                            lockDuration = duration
                            confirmsLock = true
                        }
                    }
                } label: {
                    Label(model.rulesLocked ? "Extend Lock" : "Lock", systemImage: "lock")
                }
                .help("Lock rules so they cannot be changed or turned off")
            }
            ToolbarItem {
                Menu {
                    Button("Import Rule Pack…") { RulePackFiles.chooseImport(model: model) }
                    Button("Export Rules…") { showsExport = true }.disabled(rules.isEmpty)
                } label: {
                    Label("Rule Pack Files", systemImage: "square.and.arrow.up")
                }
            }
            ToolbarItem {
                Button {
                    showsTemplates = true
                } label: {
                    Label("Add Rules", systemImage: "plus")
                }
                .help("Add rules from the Library")
            }
        }
        .confirmationDialog("Lock your rules?", isPresented: $confirmsLock) {
            Button("Lock") { model.lockRules(until: lockDuration.end) }
        } message: {
            Text("Until \(lockDuration.end.formatted(date: .abbreviated, time: .shortened)) there is no way to unlock early.")
        }
        .sheet(isPresented: $showsTemplates) {
            TemplatePicker { template in
                showsTemplates = false
                editing = template.make()
            }
        }
        .sheet(isPresented: $showsExport) {
            RulePackExportPicker(rules: rules)
        }
        .sheet(item: $editing) { rule in
            RuleEditor(rule: rule, isNew: !rules.contains { $0.id == rule.id }, undoManager: undoManager)
        }
    }
}

private struct RuleRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
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
                        Text(RuleSentence(rule: rule).text)
                            .font(Theme.Font.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: Theme.Space.m)
                    VStack(alignment: .trailing, spacing: Theme.Space.xs) {
                        if let minutes = rule.limits.dailyMinutes {
                            Text("\(Format.duration(usage.seconds)) / \(Format.minutesLabel(minutes)) today")
                                .font(Theme.Font.caption).monospacedDigit()
                            ProportionBar(
                                fraction: minutes > 0 ? usage.seconds / Double(minutes * 60) : 1,
                                color: usage.seconds >= Double(minutes * 60) ? Theme.caution : Theme.accent)
                                .frame(width: 112)
                        } else if rule.limits.dailyOpens == nil {
                            Text("\(Format.duration(usage.seconds)) today")
                                .font(Theme.Font.caption).monospacedDigit()
                        }
                        if let opens = rule.limits.dailyOpens {
                            Text("\(usage.opens) / \(opens) opens today")
                                .font(Theme.Font.caption).monospacedDigit()
                            ProportionBar(
                                fraction: opens > 0 ? Double(usage.opens) / Double(opens) : 1,
                                color: usage.opens >= opens ? Theme.caution : Theme.accent)
                                .frame(width: 112)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit \(rule.name)")
            Toggle(
                "Enabled",
                isOn: Binding(get: { rule.isEnabled }, set: { model.setEnabled($0, rule: rule, undoManager: undoManager) })
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .accessibilityLabel("Enable \(rule.name)")
            .disabled(!isEditable)
            .help(isEditable ? "Turn this rule on or off" : "Locked")
        }
        .padding(.vertical, 6)
        .contextMenu {
            Button("Edit\u{2026}", action: open)
            Divider()
            Button("Delete", role: .destructive) {
                model.delete(rule: rule, undoManager: undoManager)
            }.disabled(!isEditable)
        }
    }
}

#if DEBUG
struct RulesListGallery: View {
    private let rules = [
        RuleTemplate.mindfulSocial.make(), RuleTemplate.newsDiet.make(),
        RuleTemplate.windDown.make(), RuleTemplate.gambling.make(),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Your Rules").font(Theme.Font.title)
            ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                RuleRow(
                    rule: rule, usage: RuleDayUsage(seconds: Double((index + 1) * 420), opens: index + 2),
                    isEditable: false, open: {})
                Divider()
            }
        }
        .padding(Theme.Space.l)
    }
}
#endif

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
    @State private var previewing: RuleTemplate?

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
                .accessibilityLabel("Library Section")
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
                            PackRow(
                                pack: pack, isAdded: isAdded(pack),
                                add: { model.add(pack: pack) },
                                preview: { previewing = $0 })
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
        .sheet(item: $previewing) { template in
            LibraryRulePreview(template: template) {
                model.save(rule: template.make())
                previewing = nil
            } customize: {
                previewing = nil
                choose(template)
            }
        }
    }

    private func isAdded(_ pack: RulePack) -> Bool {
        let names = Set(model.configuration.rules.map(\.name))
        return pack.templates.allSatisfy { names.contains($0.make().name) }
    }

    private func templateRow(_ template: RuleTemplate) -> some View {
        Button {
            previewing = template
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
        .accessibilityLabel("Preview \(template.title)")
    }
}

private struct PackRow: View {
    let pack: RulePack
    let isAdded: Bool
    let add: () -> Void
    let preview: (RuleTemplate) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            LibrarySymbol(symbol: pack.symbol)
            VStack(alignment: .leading, spacing: 4) {
                Text(pack.title).font(Theme.Font.body.weight(.semibold))
                Text(pack.subtitle).font(Theme.Font.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                FlowLayout(spacing: 6) {
                    ForEach(pack.templates) { template in
                        Button { preview(template) } label: {
                            Chip(title: template.title, symbol: template.symbol)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Preview \(template.title)")
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
                    .accessibilityLabel("Add \(pack.title) Pack")
            }
        }
        .padding(.vertical, 10)
    }
}

private struct LibrarySymbol: View {
    let symbol: String
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15))
            .foregroundStyle(Theme.accent)
            .frame(width: 32, height: 32)
            .background(Theme.accentSoft(contrast), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct LibraryRulePreview: View {
    @Environment(\.dismiss) private var dismiss
    let template: RuleTemplate
    let add: () -> Void
    let customize: () -> Void

    var body: some View {
        let rule = template.make()
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(template.title).font(Theme.Font.title).accessibilityAddTraits(.isHeader)
            Text(template.subtitle).font(Theme.Font.body).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionTitle(title: "Targets")
                    ForEach(rule.targets) { target in
                        Label(target.displayName, systemImage: target.symbol)
                            .font(Theme.Font.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !rule.exceptions.isEmpty {
                        SectionTitle(title: "Except")
                        ForEach(rule.exceptions) { target in
                            Label(target.displayName, systemImage: target.symbol).font(Theme.Font.body)
                        }
                    }
                    SectionTitle(title: "Schedule")
                    Text(schedule(rule)).font(Theme.Font.body)
                    SectionTitle(title: "Response")
                    Text(rule.summary).font(Theme.Font.body)
                    RuleShieldPreview(rule: rule)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Customize…", action: customize)
                Button("Add Rule", action: add)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.l)
        .frame(width: 480, height: 640)
    }

    private func schedule(_ rule: Rule) -> String {
        switch rule.schedule {
        case .always: "All the time"
        case .duringFocus: "Only during Focus"
        case .windows(let windows): windows.map(\.summary).joined(separator: "\n")
        }
    }
}
