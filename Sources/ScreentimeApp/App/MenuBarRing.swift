import AppKit
import SwiftUI

/// A status-item-sized goal ring, cached at whole percentages rather than timer ticks.
struct MenuBarRing: View {
    let fraction: Double
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: MenuBarRingImage.image(fraction: fraction, dark: colorScheme == .dark))
            .frame(width: 16, height: 16)
            .accessibilityLabel(fraction > 1 ? "Over your distracting time goal" : "Distracting time, \(percentage) percent of your goal")
    }

    private var percentage: Int {
        Int((min(1, max(0, fraction)) * 100).rounded())
    }
}

@MainActor
private enum MenuBarRingImage {
    private static var images: [Int: NSImage] = [:]

    static func image(fraction: Double, dark: Bool) -> NSImage {
        let overGoal = fraction > 1
        let percentage = Int((min(1, max(0, fraction)) * 100).rounded())
        let key = overGoal ? (dark ? 102 : 101) : percentage
        if let image = images[key] { return image }

        let image = NSImage(size: NSSize(width: 16, height: 16))
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        appearance.performAsCurrentDrawingAppearance {
            for scale in [1, 2] {
                guard let representation = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: 16 * scale, pixelsHigh: 16 * scale,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                    let context = NSGraphicsContext(bitmapImageRep: representation)
                else { continue }
                representation.size = NSSize(width: 16, height: 16)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
                let color = overGoal ? NSColor(Theme.caution) : NSColor.black
                color.withAlphaComponent(0.25).setStroke()
                let track = NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 12, height: 12))
                track.lineWidth = 2
                track.stroke()
                color.setStroke()
                if percentage == 100 || overGoal {
                    track.stroke()
                } else if percentage > 0 {
                    let arc = NSBezierPath()
                    arc.lineWidth = 2
                    arc.lineCapStyle = .round
                    arc.appendArc(
                        withCenter: NSPoint(x: 8, y: 8), radius: 6,
                        startAngle: 90, endAngle: 90 - CGFloat(percentage) * 3.6, clockwise: true)
                    arc.stroke()
                }
                NSGraphicsContext.restoreGraphicsState()
                image.addRepresentation(representation)
            }
        }
        image.isTemplate = !overGoal
        images[key] = image
        return image
    }
}

#if DEBUG
struct MenuBarRingGallery: View {
    private let fractions = [0.0, 0.01, 0.25, 0.5, 0.75, 1, 1.25]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text("Your Daily Goal").font(Theme.Font.title)
            Text("Distracting time fills the ring. Amber means you’re over your goal.")
                .font(Theme.Font.body).foregroundStyle(.secondary)
            HStack(spacing: Theme.Space.l) {
                ForEach(fractions, id: \.self) { fraction in
                    VStack(spacing: Theme.Space.s) {
                        MenuBarRing(fraction: fraction)
                        Text("\(Int(fraction * 100))%")
                            .font(Theme.Font.caption).monospacedDigit()
                    }
                }
            }
            HStack(spacing: Theme.Space.s) {
                MenuBarRing(fraction: 0.5)
                Text("24:59").monospacedDigit()
                Text("Focus running").foregroundStyle(.secondary)
            }
            .font(Theme.Font.body)
        }
        .padding(Theme.Space.l)
    }
}
#endif
