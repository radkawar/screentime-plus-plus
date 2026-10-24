import ScreentimeCore
import SwiftUI

/// The card drawn over a shielded window. Opaque and calm on purpose: it must
/// not show what it is covering, and it must not be more stimulating than
/// what it replaced.
struct ShieldCard: View {
    @Bindable var presentation: ShieldPresentation
    let coordinator: ShieldCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.canvas
            VStack(spacing: Theme.Space.l) {
                Spacer(minLength: Theme.Space.l)
                header
                if let pause = presentation.pause {
                    PauseBody(presentation: presentation, pause: pause, coordinator: coordinator)
                } else if let block = presentation.block {
                    BlockBody(presentation: presentation, block: block, coordinator: coordinator)
                }
                Spacer(minLength: Theme.Space.l)
                footer
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: 520)
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: presentation.isBrowser ? 0 : 10, bottomLeadingRadius: 10,
                bottomTrailingRadius: 10, topTrailingRadius: presentation.isBrowser ? 0 : 10))
        .tint(Theme.ember)
    }

    private var header: some View {
        VStack(spacing: Theme.Space.s) {
            Text(presentation.subject)
                .font(Theme.Font.label)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
            Text(title)
                .font(Theme.Font.display(34))
                .multilineTextAlignment(.center)
            Text(detail)
                .font(Theme.Font.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if presentation.pause != nil {
            return presentation.phase == .waiting ? "Take a breath." : "Still want to go in?"
        }
        guard let block = presentation.block else { return "" }
        switch block.reason {
        case .focus: return "You\u{2019}re focusing."
        case .minutesLimit: return "That\u{2019}s today\u{2019}s time."
        case .opensLimit: return "That\u{2019}s today\u{2019}s opens."
        case .rule: return "Not this one."
        }
    }

    private var detail: String {
        let rule = presentation.rule
        if let pause = presentation.pause {
            let opens =
                pause.opensToday == 0
                ? "First open today" : "Opened \(pause.opensToday) time\(pause.opensToday == 1 ? "" : "s") today"
            return "\(rule.name) \u{00B7} \(opens)"
        }
        guard let block = presentation.block else { return "" }
        let evidence = evidenceLine(block.match.evidence)
        switch block.reason {
        case .focus(let title, let until, _):
            return "\(title) until \(Format.clock(until))"
        case .minutesLimit(let minutes):
            return "\(rule.name) allows \(Format.minutesLabel(minutes)) a day. It opens again tomorrow."
        case .opensLimit(let opens):
            return "\(rule.name) allows \(opens) open\(opens == 1 ? "" : "s") a day. It opens again tomorrow."
        case .rule:
            if let until = block.until {
                return "\(rule.name) until \(Format.clock(until))\(evidence)"
            }
            return "\(rule.name)\(evidence)"
        }
    }

    private func evidenceLine(_ evidence: MatchEvidence) -> String {
        if case .phrases = evidence { return " \u{00B7} \(evidence.summary)" }
        return ""
    }

    private var footer: some View {
        Label("Screentime++", systemImage: "hourglass")
            .font(Theme.Font.caption)
            .foregroundStyle(.tertiary)
            .labelStyle(.titleAndIcon)
    }
}

private struct PauseBody: View {
    @Bindable var presentation: ShieldPresentation
    let pause: PauseIntervention
    let coordinator: ShieldCoordinator

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            BreathingRing(
                remaining: presentation.remaining, total: TimeInterval(pause.waitSeconds),
                isWaiting: presentation.phase == .waiting)
            if pause.asksIntention {
                TextField("What are you here for?", text: $presentation.intention)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                    .multilineTextAlignment(.center)
            }
            if presentation.phase == .choosing {
                VStack(spacing: Theme.Space.m) {
                    HStack(spacing: Theme.Space.s) {
                        ForEach(pause.sessionMinutes, id: \.self) { minutes in
                            Button("\(minutes) min") { coordinator.choose(minutes: minutes) }
                                .buttonStyle(ShieldButtonStyle(prominent: false))
                        }
                    }
                    Button(presentation.isBrowser ? "Not now, close the tab" : "Not now, hide \(presentation.appName)") {
                        coordinator.closeTabOrHide()
                    }
                    .buttonStyle(ShieldButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                }
                .transition(.opacity)
            } else {
                Button(presentation.isBrowser ? "Close the tab instead" : "Hide \(presentation.appName) instead") {
                    coordinator.closeTabOrHide()
                }
                .buttonStyle(.plain)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.ember)
            }
        }
        .animation(.easeOut(duration: 0.2), value: presentation.phase)
    }
}

private struct BlockBody: View {
    let presentation: ShieldPresentation
    let block: BlockIntervention
    let coordinator: ShieldCoordinator

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            Image(systemName: presentation.rule.symbol)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Theme.ember)
                .frame(width: 72, height: 72)
                .background(Theme.emberSoft, in: Circle())
                .accessibilityHidden(true)
            HStack(spacing: Theme.Space.s) {
                if presentation.isBrowser {
                    Button("Close Tab") { coordinator.closeTabOrHide() }
                        .buttonStyle(ShieldButtonStyle(prominent: true))
                        .keyboardShortcut(.defaultAction)
                    if !presentation.isParked {
                        Button("Go Back") { coordinator.goBack() }
                            .buttonStyle(ShieldButtonStyle(prominent: false))
                    }
                } else {
                    Button("Quit \(presentation.appName)") { coordinator.quitApp() }
                        .buttonStyle(ShieldButtonStyle(prominent: true))
                        .keyboardShortcut(.defaultAction)
                    Button("Hide") { coordinator.closeTabOrHide() }
                        .buttonStyle(ShieldButtonStyle(prominent: false))
                }
            }
            if block.allowsOverride, !block.closesAutomatically {
                HoldToConfirmButton(title: "Hold to allow 1 minute") {
                    coordinator.overrideOneMinute()
                }
            } else if block.closesAutomatically {
                Text(presentation.isBrowser ? "Closing this tab\u{2026}" : "Quitting \(presentation.appName)\u{2026}")
                    .font(Theme.Font.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The pause signature: a ring that drains while a soft disc breathes in
/// four-second cycles. With Reduce Motion the disc stays still.
struct BreathingRing: View {
    let remaining: TimeInterval
    let total: TimeInterval
    let isWaiting: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isWaiting || reduceMotion)) { timeline in
            let phase = breathPhase(timeline.date)
            ZStack {
                Circle()
                    .fill(Theme.emberSoft)
                    .scaleEffect(reduceMotion || !isWaiting ? 0.82 : 0.62 + 0.3 * phase)
                Circle()
                    .stroke(Theme.track, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: total > 0 ? remaining / total : 0)
                    .stroke(Theme.ember, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    if isWaiting {
                        Text("\(Int(remaining.rounded(.up)))")
                            .font(Theme.Font.display(40))
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                        Text(phase > 0.5 ? "breathe out" : "breathe in")
                            .font(Theme.Font.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(Theme.ember)
                    }
                }
            }
            .frame(width: 150, height: 150)
        }
        .accessibilityElement()
        .accessibilityLabel(isWaiting ? "\(Int(remaining.rounded(.up))) seconds left" : "Wait finished")
    }

    /// 0 -> 1 -> 0 over an eight-second breath, eased.
    private func breathPhase(_ date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 8) / 8
        return (1 - cos(t * 2 * .pi)) / 2
    }
}

/// An override that has to be meant: press and hold for two seconds while a
/// ring fills. Releasing early resets it.
struct HoldToConfirmButton: View {
    let title: String
    var duration: TimeInterval = 2
    let action: () -> Void

    @State private var isPressing = false
    @State private var progress: Double = 0

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            ZStack {
                Circle().stroke(Theme.track, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Theme.ember, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
            Text(title)
                .font(Theme.Font.body)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(height: 32)
        .contentShape(Capsule())
        .background(Capsule().fill(isPressing ? Theme.track : .clear))
        .onLongPressGesture(minimumDuration: duration, maximumDistance: 30) {
            progress = 1
            action()
        } onPressingChanged: { pressing in
            isPressing = pressing
            if pressing {
                withAnimation(.linear(duration: duration)) { progress = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
        .help("Press and hold for two seconds")
    }
}

/// Plain cover for an app's other windows; the card sits on the front one.
struct ShieldCover: View {
    let ruleName: String
    let symbol: String

    var body: some View {
        ZStack {
            Theme.canvas
            Label(ruleName, systemImage: symbol)
                .font(Theme.Font.body)
                .foregroundStyle(.secondary)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// The shield panel never becomes key, so system prominent buttons would draw
/// in their inactive grey. This style keeps the ember fill regardless.
struct ShieldButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.body.weight(.medium))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, Theme.Space.m)
            .frame(minWidth: 88, minHeight: 32)
            .background(
                Capsule().fill(prominent ? Theme.ember : Theme.track)
            )
            .overlay(Capsule().strokeBorder(prominent ? Color.clear : Theme.hairline, lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}
