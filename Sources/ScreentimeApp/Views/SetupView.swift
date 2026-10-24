import ScreentimeCore
import SwiftUI

/// First run: one permission, a few starting rules, a goal.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    @State private var chosen: Set<String> = ["essentials"]
    @State private var goal = 90
    @State private var showsPauseDemo = false
    @State private var finishedPauseDemo = false

    private let packs = RulePack.all

    /// Templates from the chosen packs, each once, in pack order.
    private var chosenTemplates: [RuleTemplate] {
        var seen = Set<String>()
        return packs.filter { chosen.contains($0.id) }.flatMap(\.templates).filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Screentime++").font(Theme.Font.display(52))
                    Text("Measures where your time goes, and stands in front of the apps, sites, and things inside them you\u{2019}d rather skip: a game, a chat app, a feed, a channel, a phrase.")
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
                                .foregroundStyle(Theme.accent)
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
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(packs) { pack in
                            Toggle(isOn: binding(pack.id)) {
                                HStack(alignment: .top, spacing: Theme.Space.s) {
                                    Image(systemName: pack.symbol).foregroundStyle(Theme.accent).frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pack.title).font(Theme.Font.body.weight(.medium))
                                        Text(pack.subtitle).font(Theme.Font.caption).foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .toggleStyle(.checkbox)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if pack.id != packs.last?.id { Divider() }
                        }
                        Text("You can add more from the Library in Rules at any time.")
                            .font(Theme.Font.caption).foregroundStyle(.secondary)
                            .padding(.top, Theme.Space.s)
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

                step(4, "See what a pause looks like") {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text("A short wait gives you a moment to choose: open a timed session, or turn back.")
                            .font(Theme.Font.body).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(finishedPauseDemo ? "Try the Pause Again" : "Try a Pause") {
                            showsPauseDemo = true
                        }
                        .linkStyle()
                        if finishedPauseDemo {
                            Label("You\u{2019}re ready. Your apps and tabs stayed as they were.", systemImage: "checkmark.circle")
                                .font(Theme.Font.caption).foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
            .padding(Theme.Space.xxl)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                if !model.isAccessibilityTrusted {
                    Text("Rules start working once Accessibility is on.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.completeSetup(templates: chosenTemplates, goalMinutes: goal)
                } label: {
                    Text("Start").frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.m)
            .background(.bar)
        }
        .toolbar(removing: .title)
        .sheet(isPresented: $showsPauseDemo) {
            SetupPauseDemo { finishedPauseDemo = true }
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
                .foregroundStyle(Theme.accent)
                .frame(width: 26, height: 26)
                .background(Theme.accentSoft, in: Circle())
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

/// Uses the real shield and countdown, but never starts enforcement or grants access.
struct SetupPauseDemo: View {
    var onComplete: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var presentation = makePresentation()
    @State private var coordinator = ShieldCoordinator()
    @State private var finished = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("See what a pause looks like").font(Theme.Font.heading)
                    Text("Try a three-second pause. Nothing will open or close.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .linkStyle()
            }
            .padding(Theme.Space.l)
            Divider()
            if finished {
                VStack(spacing: Theme.Space.m) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 36)).foregroundStyle(Theme.accent)
                    Text("That\u{2019}s a pause.").font(Theme.Font.display(34))
                    Text("You choose a short session or turn back.\nYour apps and tabs stayed as they were.")
                        .font(Theme.Font.body).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Done") { dismiss() }
                        .buttonStyle(ShieldButtonStyle(prominent: true))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(Theme.Space.l)
            } else {
                ShieldCard(presentation: presentation, coordinator: coordinator, onDemoComplete: {
                    presentation.stopClock()
                    finished = true
                    onComplete()
                })
            }
        }
        .frame(width: 560, height: 620)
        .background(Theme.canvas)
        .onAppear { presentation.startClock() }
        .onDisappear { presentation.stopClock() }
    }

    private static func makePresentation() -> ShieldPresentation {
        let context = ForegroundContext(
            bundleID: "com.apple.Safari", appName: "Safari", pid: 0,
            isBrowser: true, url: URL(string: "https://www.reddit.com/"))
        let rule = Rule(
            name: "Pause Reddit", targets: [.website(domain: "reddit.com")],
            response: .pause(PauseSettings(waitSeconds: 3, escalationSeconds: 0, asksIntention: false)))
        let now = Date()
        guard let intervention = PolicyEngine.evaluate(
            context: context, content: nil, rules: [rule], runtime: RuleRuntime(), now: now
        ).intervention else {
            preconditionFailure("The setup pause must match its sample site.")
        }
        return ShieldPresentation(intervention: intervention, context: context, now: now)
    }
}
