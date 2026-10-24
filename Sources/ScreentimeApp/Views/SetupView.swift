import ScreentimeCore
import SwiftUI

/// First run: one permission, a few starting rules, a goal.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    @State private var chosen: Set<String> = [RuleTemplate.minimalYouTube.id, RuleTemplate.mindfulSocial.id]
    @State private var goal = 90

    private let templates = RuleTemplate.all.filter { $0.id != RuleTemplate.blank.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Screentime++").font(Theme.Font.display(52))
                    Text("Measures where your time goes and stands in front of the parts of the web you\u{2019}d rather skip: a page, a feed, a phrase, not just a whole site.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                step(1, "Allow Accessibility") {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text("Screentime++ reads the app, address and text in front of you to measure time and apply your rules. It all stays on this Mac.")
                            .font(Theme.Font.body).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if model.isAccessibilityTrusted {
                            Label("Accessibility is on", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Theme.color(for: .productivity))
                        } else {
                            HStack(spacing: Theme.Space.m) {
                                Button("Open Accessibility Settings\u{2026}") { model.requestAccessibility() }
                                    .buttonStyle(.borderedProminent)
                                Text("Turn on Screentime++, then come back.")
                                    .font(Theme.Font.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                step(2, "Choose where to start") {
                    VStack(spacing: 0) {
                        ForEach(templates) { template in
                            Toggle(isOn: binding(template.id)) {
                                HStack(alignment: .top, spacing: Theme.Space.s) {
                                    Image(systemName: template.symbol).foregroundStyle(Theme.ember).frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(template.title).font(Theme.Font.body.weight(.medium))
                                        Text(template.subtitle).font(Theme.Font.caption).foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .toggleStyle(.checkbox)
                            .padding(.vertical, 7)
                            if template.id != templates.last?.id { Divider() }
                        }
                    }
                }

                step(3, "Set a daily goal") {
                    HStack {
                        Stepper(value: $goal, in: 10...600, step: 10) {
                            Text("\(Format.duration(TimeInterval(goal * 60))) of distracting time a day")
                                .monospacedDigit()
                        }
                        .fixedSize()
                    }
                }

                HStack {
                    Spacer()
                    Button {
                        model.completeSetup(templates: templates.filter { chosen.contains($0.id) }, goalMinutes: goal)
                    } label: {
                        Text("Start").frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(Theme.Space.xxl)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task {
            // Notice the permission as soon as it is granted in System Settings.
            while !Task.isCancelled, !model.isAccessibilityTrusted {
                try? await Task.sleep(for: .seconds(1))
                model.refreshNow()
            }
        }
    }

    private func step<Content: View>(_ number: Int, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Text("\(number)")
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.ember)
                .frame(width: 26, height: 26)
                .background(Theme.emberSoft, in: Circle())
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(title).font(Theme.Font.heading)
                content()
            }
        }
    }

    private func binding(_ id: String) -> Binding<Bool> {
        Binding(get: { chosen.contains(id) }, set: { if $0 { chosen.insert(id) } else { chosen.remove(id) } })
    }
}
