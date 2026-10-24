#if DEBUG
    import AppKit
    import ScreentimeCore
    import Sparkle
    import SwiftUI

    /// Design-review gallery for Debug builds. Launch with `--qa-gallery` (and
    /// `SCREENTIME_DATA_DIR` pointing at a scratch folder) to open every sheet,
    /// settings pane, the menu bar panel and each shield variant in its own
    /// titled window, so each can be captured by window ID without driving the UI.
    @MainActor
    enum QAGallery {
        private static var windows: [NSWindow] = []

        static func presentIfRequested(model: AppModel, updater: SPUUpdater) {
            guard CommandLine.arguments.contains("--qa-gallery") else { return }
            let env = { (view: AnyView) in AnyView(view.environment(model).tint(Theme.accent)) }
            open(
                "Widget Small", size: CGSize(width: 170, height: 170),
                AnyView(TodayWidgetView(snapshot: .sample).padding(16).background(Theme.canvas)))
            open(
                "Widget Medium", size: CGSize(width: 360, height: 170),
                AnyView(TodayWidgetView(snapshot: .sample, isMedium: true).padding(16).background(Theme.canvas)))
            var overGoalWidget = WidgetSnapshot.sample
            overGoalWidget.distractingSeconds = 75 * 60
            open(
                "Widget Over Goal", size: CGSize(width: 360, height: 170),
                AnyView(TodayWidgetView(snapshot: overGoalWidget, isMedium: true).padding(16).background(Theme.canvas)))


            // Rule editor, one per response shape.
            var slack = Rule(
                name: "Slack #random", symbol: "bubble.left.and.bubble.right",
                targets: [
                    .content(
                        ContentRule(
                            phrases: ["random", "memes"], minimumMatches: 1, scope: .titleAndAddress,
                            apps: ["com.tinyspeck.slackmacgap"]))
                ],
                exceptions: [.app(bundleID: "com.apple.Music", name: "Music")],
                response: .block(BlockSettings(allowsOverride: true, closesAutomatically: false)))
            slack.message = "Back to the channel you came for."
            let editors: [(String, Rule)] = [
                ("Sentence Pause", RuleTemplate.mindfulSocial.make()),
                ("Sentence Schedule", RuleTemplate.windDown.make()),
                ("Sentence Limit", RuleTemplate.newsDiet.make()),
                ("Sentence Block", RuleTemplate.minimalYouTube.make()),
                ("Sentence Content", slack),
            ]
            for (title, rule) in editors {
                open(title, size: CGSize(width: 580, height: 720), env(AnyView(RuleEditor(rule: rule, isNew: false))))
            }
            open("Rules List", size: CGSize(width: 780, height: 480), env(AnyView(RulesListGallery())))
            for kind in TargetComposer.Kind.allCases {
                open(
                    "Composer \(kind.rawValue)", size: CGSize(width: 520, height: 460),
                    env(AnyView(TargetComposer(initialKind: kind) { _ in })))
            }
            open("Library Packs", size: CGSize(width: 540, height: 600), env(AnyView(TemplatePicker(initialTab: .packs) { _ in })))
            open("Library Rules", size: CGSize(width: 540, height: 600), env(AnyView(TemplatePicker(initialTab: .rules) { _ in })))
            open(
                "Today First Day", size: CGSize(width: 780, height: 560),
                env(AnyView(TodayFirstDayState(appName: "Safari", browse: {}).padding(Theme.Space.xl))))
            open(
                "History First Days", size: CGSize(width: 780, height: 400),
                env(AnyView(HistoryFirstDaysState().padding(Theme.Space.xl))))
            open(
                "Day Detail", size: CGSize(width: 780, height: 760),
                env(AnyView(DayDetailView(day: HistoryDetailSamples.day, sample: HistoryDetailSamples.summary))))
            for (name, subject) in [("Site", HistoryDetailSamples.site), ("App", HistoryDetailSamples.app)] {
                open(
                    "Item Detail \(name)", size: CGSize(width: 640, height: 700),
                    env(AnyView(ItemDetailView(
                        subject: subject,
                        sampleReport: HistoryDetailSamples.week.filtered(for: subject),
                        sampleWeek: HistoryDetailSamples.week.filtered(for: subject),
                        sampleRules: [HistoryDetailSamples.rule]))))
            }
            open(
                "Editor Shield Preview", size: CGSize(width: 420, height: 360),
                env(AnyView(RuleShieldPreview(rule: slack).padding(Theme.Space.l))))
            open(
                "Library Rule Preview", size: CGSize(width: 480, height: 640),
                env(AnyView(LibraryRulePreview(template: .mindfulSocial, add: {}, customize: {}))))
            open(
                "Increased Contrast", size: CGSize(width: 540, height: 600),
                env(AnyView(TemplatePicker(initialTab: .packs) { _ in })),
                appearance: NSAppearance(named: .accessibilityHighContrastAqua))
            open(
                "Weekly Review", size: CGSize(width: 680, height: 800),
                AnyView(NavigationStack { WeeklyReviewView(review: .gallery) }))

            let panes: [(String, AnyView)] = [
                ("Settings General", AnyView(GeneralSettings())),
                ("Settings Shields", AnyView(ShieldSettings())),
                ("Settings Idle", AnyView(Form { IdleSettings() }.formStyle(.grouped))),
                ("Settings Screen Time Import", AnyView(Form { ScreenTimeImportSettings() }.formStyle(.grouped))),
                ("Settings Lock", AnyView(LockSettings())),
                ("Settings Privacy & Data", AnyView(PrivacySettings())),
                ("Settings Notifications", AnyView(NotificationSettings())),
                ("Settings Updates", AnyView(UpdateSettings(updater: updater))),
            ]
            for (title, pane) in panes {
                open(title, size: CGSize(width: 520, height: 520), env(AnyView(pane.frame(width: 520))))
            }
            open(
                "Settings Search", size: CGSize(width: 620, height: 400),
                env(AnyView(SettingsView(updater: updater, initialSearch: "history"))))
            open(
                "Import Rule Pack", size: CGSize(width: 520, height: 440),
                env(AnyView(RulePackImportPreview(rules: [RuleTemplate.mindfulSocial.make(), RuleTemplate.windDown.make()]))))
            open(
                "Export Rules", size: CGSize(width: 480, height: 440),
                env(AnyView(RulePackExportPicker(rules: model.configuration.rules))))
            open("Menu Bar", size: CGSize(width: 320, height: 360), env(AnyView(MenuBarView())))
            let frontSite = DraftSubject(bundleID: "com.apple.Safari", appName: "Safari",
                                         domain: "youtube.com", surface: "Shorts")
            let frontApp = DraftSubject(bundleID: "com.tinyspeck.slackmacgap", appName: "Slack")
            let covered = RuleDraft.rule(for: frontSite, kind: .pause)
            let sampleNow = Date()
            let frontRows: [(String, InFrontRow)] = [
                ("Menu Bar In Front Site", InFrontRow(subject: frontSite, draft: { _ in }, edit: { _ in })),
                ("Menu Bar In Front App", InFrontRow(subject: frontApp, draft: { _ in }, edit: { _ in })),
                ("Menu Bar In Front Covered", InFrontRow(subject: frontSite, coveredRule: covered, draft: { _ in }, edit: { _ in })),
                ("Menu Bar Session Countdown", InFrontRow(subject: frontSite, coveredRule: covered,
                    grant: AccessGrant(ruleID: covered.id, until: sampleNow.addingTimeInterval(132), kind: .session),
                    now: sampleNow, draft: { _ in }, edit: { _ in })),
                ("Menu Bar Override Countdown", InFrontRow(subject: frontSite, coveredRule: covered,
                    grant: AccessGrant(ruleID: covered.id, until: sampleNow.addingTimeInterval(42), kind: .override),
                    now: sampleNow, draft: { _ in }, edit: { _ in })),
            ]
            for (title, row) in frontRows {
                open(title, size: CGSize(width: 320, height: 220), env(AnyView(row.padding(Theme.Space.m))))
            }
            open("Menu Bar Goal Ring", size: CGSize(width: 440, height: 240), env(AnyView(MenuBarRingGallery())))
            open(
                "Focus Arc", size: CGSize(width: 360, height: 360),
                AnyView(FocusArc(progress: 0.62, remaining: 31 * 60 + 12).frame(width: 260, height: 260).padding(48)))
            let writing = FocusProfile(name: "Writing")
            let study = FocusProfile(name: "Study", minutes: 90, isLocked: true,
                                     categories: [.social, .entertainment, .games])
            open("Focus Setup by Intent", size: CGSize(width: 780, height: 800),
                 env(AnyView(FocusView(isGallery: true))))
            open("Focus Profiles", size: CGSize(width: 600, height: 320),
                 AnyView(FocusProfilesView(profiles: [writing, study], defaultID: writing.id,
                                           start: { _ in }, edit: { _ in }, makeDefault: { _ in },
                                           delete: { _ in }).padding(Theme.Space.xl).tint(Theme.accent)))
            open("Running Focus", size: CGSize(width: 680, height: 680),
                 AnyView(FocusRunningView(focus: writing.session(start: Date().addingTimeInterval(-600)),
                                          rules: [], extend: {}, end: {}).padding(Theme.Space.xl)))
            open("Setup Pause Demo", size: CGSize(width: 560, height: 620), AnyView(SetupPauseDemo()))
            open(
                "Time Nudge Site", size: CGSize(width: 440, height: 160),
                AnyView(ToastView(title: "20 minutes on reddit.com", detail: "Time in this visit", symbol: "clock")))
            open(
                "Time Nudge App", size: CGSize(width: 440, height: 160),
                AnyView(ToastView(title: "30 minutes on Slack", detail: "Time in this visit", symbol: "clock")))
            open(
                "Session Ending Nudge", size: CGSize(width: 480, height: 160),
                AnyView(ToastView(
                    title: "2 minutes left on x.com", detail: "Your pause returns when this session ends.", symbol: "hourglass")))

            for (title, context, rule, runtime) in shieldCases() {
                guard
                    let intervention = PolicyEngine.evaluate(
                        context: context, content: nil, rules: [rule], runtime: runtime, now: Date()
                    ).intervention
                else { continue }
                let presentation = ShieldPresentation(intervention: intervention, context: context, now: Date())
                presentation.isParked = context.isBrowser
                open(
                    title, size: CGSize(width: 760, height: 620),
                    AnyView(ShieldCard(
                        presentation: presentation, coordinator: model.shields,
                        showsEvidence: title.hasPrefix("Shield Evidence"))))
            }
            Toast.show(title: "Turned back", detail: "9 times today", symbol: "arrow.uturn.backward")
        }

        private static func shieldCases() -> [(String, ForegroundContext, Rule, RuleRuntime)] {
            let safari = { (url: String) in
                ForegroundContext(
                    bundleID: "com.apple.Safari", appName: "Safari", pid: 1, isBrowser: true, url: URL(string: url))
            }
            let slack = ForegroundContext(
                bundleID: "com.tinyspeck.slackmacgap", appName: "Slack", pid: 2, isBrowser: false,
                windowTitle: "random (Channel) - Acme - Slack")
            var instant = RuleTemplate.mindfulSocial.make()
            instant.response = .pause(PauseSettings(waitSeconds: 0, escalationSeconds: 0))
            let news = RuleTemplate.newsDiet.make()
            let focusRule = RuleTemplate.focusBlocklist.make()
            let focus = FocusSession(
                title: "Deep work", start: Date().addingTimeInterval(-600), end: Date().addingTimeInterval(2_400),
                ruleIDs: [focusRule.id], isLocked: true)
            let chat = RuleTemplate.chatApps.make()
            var chatBlock = chat
            chatBlock.response = .block(BlockSettings(allowsOverride: true, closesAutomatically: false))
            var casino = safari("https://casino.example/")
            casino.pageTitle = "Online casino: free spins, roulette and blackjack"
            var phraseBlock = RuleTemplate.gambling.make()
            phraseBlock.response = .block(BlockSettings(allowsOverride: true, closesAutomatically: false))
            return [
                ("Shield Pause Waiting", safari("https://x.com/home"), RuleTemplate.mindfulSocial.make(), RuleRuntime()),
                ("Shield Pause Choosing", safari("https://x.com/home"), instant, RuleRuntime()),
                ("Shield Block Web", safari("https://www.youtube.com/shorts/abc"), RuleTemplate.minimalYouTube.make(), RuleRuntime()),
                ("Shield Block App", slack, chatBlock, RuleRuntime()),
                ("Shield Limit", safari("https://www.nytimes.com/"), news, RuleRuntime(usageSeconds: [news.id: 1_800])),
                ("Shield Focus Locked", safari("https://www.reddit.com/"), focusRule, RuleRuntime(focus: focus)),
                ("Shield Auto Close", casino, RuleTemplate.gambling.make(), RuleRuntime()),
                ("Shield Evidence Web Phrases", casino, phraseBlock, RuleRuntime()),
                ("Shield Evidence App", slack, chatBlock, RuleRuntime()),
                ("Shield Evidence Limit", safari("https://www.nytimes.com/"), news, RuleRuntime(usageSeconds: [news.id: 1_800])),
            ]
        }

        private static func open(_ title: String, size: CGSize, _ view: AnyView, appearance: NSAppearance? = nil) {
            let offset = CGFloat(windows.count % 12) * 24
            let window = NSWindow(
                contentRect: NSRect(x: 60 + offset, y: 60 + offset, width: size.width, height: size.height),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "QA \(title)"
            window.isReleasedWhenClosed = false
            window.appearance = appearance
            let hosting = NSHostingView(rootView: view)
            // The window owns its size; a hosting view that also drives window
            // size extrema can loop AppKit's constraint pass.
            hosting.sizingOptions = []
            window.contentView = hosting
            window.orderFront(nil)
            windows.append(window)
        }
    }
#endif
