import AppKit
import ScreentimeCore
import SwiftUI

/// Design tokens. See docs/DESIGN.md.
enum Theme {
    /// Positive and primary: controls, selection, "on track", turning back.
    static let accent = Color(light: 0x2E7D57, dark: 0x3FAE77)
    static let accentSoft = contrastAdaptive(accent, normal: 0.14, increased: 0.26)
    /// Attention without alarm: over goal, overrides, missing permission.
    static let caution = Color(light: 0xB26B12, dark: 0xE3A040)
    static let cautionSoft = contrastAdaptive(caution, normal: 0.14, increased: 0.26)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let hairline = contrastAdaptive(Color.primary, normal: 0.16, increased: 0.48)
    static let track = contrastAdaptive(Color.primary, normal: 0.07, increased: 0.18)

    /// Environment-aware counterparts also support SwiftUI contrast overrides
    /// (including the QA gallery), rather than only the system appearance.
    static func track(_ contrast: ColorSchemeContrast) -> Color {
        contrast == .increased ? Color.primary.opacity(0.18) : track
    }

    static func hairline(_ contrast: ColorSchemeContrast) -> Color {
        contrast == .increased ? Color.primary.opacity(0.48) : hairline
    }

    static func accentSoft(_ contrast: ColorSchemeContrast) -> Color {
        contrast == .increased ? accent.opacity(0.26) : accentSoft
    }

    private static func contrastAdaptive(_ color: Color, normal: Double, increased: Double) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [
                .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
            ])
            let high = match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua
            return NSColor(color).withAlphaComponent(high ? increased : normal)
        })
    }

    static func color(for category: UsageCategory) -> Color {
        switch category {
        case .social: Color(light: 0xD9623F, dark: 0xEE7E5E)
        case .entertainment: Color(light: 0x9A5A86, dark: 0xC083AE)
        case .productivity: Color(light: 0x4A72A8, dark: 0x7FA4D6)
        case .communication: Color(light: 0x3A8592, dark: 0x66B2BE)
        case .reading: Color(light: 0xB88A2E, dark: 0xDDB25A)
        case .games: Color(light: 0xC4566F, dark: 0xE27E95)
        case .shopping: Color(light: 0xC97C34, dark: 0xE9A05E)
        case .other: Color(light: 0x8F887F, dark: 0xA9A299)
        }
    }

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Radius {
        static let chip: CGFloat = 8
        static let panel: CGFloat = 12
        static let shield: CGFloat = 20
    }

    enum Font {
        static func display(_ size: CGFloat = 48) -> SwiftUI.Font {
            .system(size: size, weight: .medium, design: .serif)
        }
        static let title = SwiftUI.Font.system(size: 28, weight: .semibold, design: .serif)
        static let heading = SwiftUI.Font.system(size: 15, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 13)
        static let caption = SwiftUI.Font.system(size: 11)
        static let label = SwiftUI.Font.system(size: 11, weight: .medium)
    }
}

extension Color {
    /// An appearance-adaptive colour from two sRGB hex values.
    init(light: UInt32, dark: UInt32) {
        self.init(
            nsColor: NSColor(name: nil) { appearance in
                let match = appearance.bestMatch(from: [
                    .aqua, .darkAqua, .vibrantLight, .vibrantDark,
                    .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
                ])
                let isDark = match == .darkAqua || match == .vibrantDark || match == .accessibilityHighContrastDarkAqua
                return NSColor(hex: isDark ? dark : light)
            })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

enum Format {
    /// "4h 12m", "38m", "45s", "0m".
    static func duration(_ seconds: TimeInterval, showSeconds: Bool = false) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return showSeconds && total > 0 ? "\(total)s" : "0m"
    }

    /// "4 hours, 12 minutes" for VoiceOver.
    static func spokenDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        if seconds <= 0 { return "0 minutes" }
        formatter.unitsStyle = .full
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        return formatter.string(from: max(60, seconds)) ?? ""
    }

    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func countdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func minutesLabel(_ minutes: Int) -> String {
        minutes >= 60 && minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes) min"
    }
}
