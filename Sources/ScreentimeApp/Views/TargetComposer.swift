import ScreentimeCore
import SwiftUI

/// Adds one target to a rule: an app, a site, a page pattern, phrases, or a category.
struct TargetComposer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    let add: (Target) -> Void

    enum Kind: String, CaseIterable, Identifiable {
        case app = "App"
        case website = "Website"
        case page = "Page"
        case phrases = "Phrases"
        case category = "Category"
        var id: String { rawValue }
    }

    @State private var kind: Kind

    init(initialKind: Kind = .app, add: @escaping (Target) -> Void) {
        _kind = State(initialValue: initialKind)
        self.add = add
    }
    @State private var apps: [InstalledApp] = []
    @State private var search = ""
    @State private var selectedApp: InstalledApp?
    @State private var website = ""
    @State private var pattern = ""
    @State private var phrases = ""
    @State private var minimumMatches = 2
    @State private var scope: ContentScope = .pageText
    @State private var category: UsageCategory = .social
    @State private var phraseApp: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Picker("Kind", selection: $kind) {
                ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Target Kind")

            Group {
                switch kind {
                case .app: appPicker
                case .website: websiteField
                case .page: patternField
                case .phrases: phraseFields
                case .category: categoryPicker
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") {
                    if let target { add(target) }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(target == nil)
            }
        }
        .padding(Theme.Space.l)
        .frame(width: 520, height: 460)
        .task {
            apps = await AppCatalog.installed()
            if website.isEmpty, let domain = model.live.context?.domain { website = domain }
        }
    }

    private var target: Target? {
        switch kind {
        case .app:
            return selectedApp.map { .app(bundleID: $0.bundleID, name: $0.name) }
        case .website:
            let domain = DomainName.normalize(website)
            return domain.contains(".") && !domain.contains(" ") ? .website(domain: domain) : nil
        case .page:
            let trimmed = pattern.trimmingCharacters(in: .whitespaces)
            return trimmed.contains(".") && !trimmed.contains(" ") ? .urlPattern(trimmed) : nil
        case .phrases:
            let list = phraseList
            return list.isEmpty
                ? nil
                : .content(
                    ContentRule(
                        phrases: list, minimumMatches: minimumMatches, scope: scope,
                        apps: phraseApp.isEmpty ? [] : [phraseApp]))
        case .category:
            return .category(category)
        }
    }

    private var phraseList: [String] {
        phrases.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var appPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            TextField("Search apps", text: $search).textFieldStyle(.roundedBorder)
            List(filteredApps, selection: $selectedApp) { app in
                HStack(spacing: Theme.Space.s) {
                    SubjectIcon(bundleID: app.bundleID, size: 20)
                    Text(app.name)
                    Spacer()
                    Text(app.bundleID).font(Theme.Font.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
                .tag(app)
            }
            .listStyle(.bordered(alternatesRowBackgrounds: false))
            .overlay { if apps.isEmpty { ProgressView() } }
        }
    }

    private var filteredApps: [InstalledApp] {
        guard !search.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.bundleID.localizedCaseInsensitiveContains(search) }
    }

    private var websiteField: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            TextField("example.com", text: $website).textFieldStyle(.roundedBorder).font(.body.monospaced())
            Text("Covers the site and every subdomain. Use Page to cover only part of a site.")
                .font(Theme.Font.caption).foregroundStyle(.secondary)
        }
    }

    private var patternField: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            TextField("youtube.com/shorts/*", text: $pattern).textFieldStyle(.roundedBorder).font(.body.monospaced())
            VStack(alignment: .leading, spacing: 4) {
                example("youtube.com/shorts/*", "every Short")
                example("reddit.com/", "the front page only")
                example("reddit.com/r/*/comments/*", "any thread")
                example("google.com/search?q=*casino*", "searches mentioning casino")
            }
            .font(Theme.Font.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func example(_ pattern: String, _ meaning: String) -> some View {
        HStack(spacing: 6) {
            Button(pattern) { self.pattern = pattern }
                .buttonStyle(.plain)
                .font(.caption.monospaced())
                .foregroundStyle(Theme.accent)
                .help("Use this pattern")
            Text(meaning)
        }
    }

    private var phraseFields: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            TextField("Phrases, separated by commas", text: $phrases, axis: .vertical)
                .lineLimit(3...5)
                .textFieldStyle(.roundedBorder)
            Stepper(value: $minimumMatches, in: 1...50) {
                Text("Match after \(minimumMatches) mention\(minimumMatches == 1 ? "" : "s") in total").monospacedDigit()
            }
            Picker("In", selection: $phraseApp) {
                Text("Any app or browser").tag("")
                Divider()
                ForEach(apps) { app in
                    Text(app.name).tag(app.bundleID)
                }
            }
            Picker("Look at", selection: $scope) {
                Text("Text, title and address").tag(ContentScope.pageText)
                Text("Title and address only").tag(ContentScope.titleAndAddress)
            }
            Text(
                "Works in apps too: a Slack channel, a Discord server or a Steam page shows up in the window title and text. Whole words, ignoring case and accents. Text is read on this Mac, checked, and discarded; it is never saved."
            )
            .font(Theme.Font.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Picker("Category", selection: $category) {
                ForEach(UsageCategory.allCases.filter { $0 != .other }) { category in
                    HStack(spacing: Theme.Space.s) {
                        Image(systemName: category.symbol).frame(width: 20)
                        Text(category.title)
                    }
                    .tag(category)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .accessibilityLabel("App and Website Category")
            let sites = CategoryCatalog.domains(in: category)
            Text(
                "Every installed app that declares itself as \(category.title.lowercased()), plus sites such as "
                    + sites.prefix(6).joined(separator: ", ") + (sites.count > 6 ? " and \(sites.count - 6) more." : ".")
            )
                .font(Theme.Font.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
