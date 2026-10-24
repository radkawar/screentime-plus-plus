#!/usr/bin/env swift
// Renders Sources/ScreentimeApp/Assets.xcassets/AppIcon.appiconset from code,
// so the icon is reproducible and reviewable. Run: swift Scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("Sources/ScreentimeApp/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = size / 1024
    context.scaleBy(x: scale, y: scale)

    // Apple's macOS grid: an 824 pt squircle centred on a 1024 canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.28))
    context.addPath(shape)
    context.setFillColor(color(0x1E1A17))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: space, colors: [color(0x2A2420), color(0x161311)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    let center = CGPoint(x: 512, y: 512)
    let radius: CGFloat = 250
    // Track.
    context.setLineWidth(64)
    context.setStrokeColor(color(0xFFFFFF, 0.08))
    context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    context.strokePath()
    // Ember arc: most of the day used, a gap left open.
    context.setLineCap(.round)
    context.setStrokeColor(color(0xF0794A))
    let start = CGFloat.pi / 2
    context.addArc(center: center, radius: radius, startAngle: start, endAngle: start - .pi * 2 * 0.72, clockwise: true)
    context.strokePath()

    // "++": two geometric plus marks in warm white, the name's only flourish.
    context.setStrokeColor(color(0xF6EFE6))
    context.setLineWidth(30)
    context.setLineCap(.round)
    let arm: CGFloat = 52
    for offset in [-70.0, 70.0] {
        let c = CGPoint(x: center.x + offset, y: center.y)
        context.move(to: CGPoint(x: c.x - arm, y: c.y))
        context.addLine(to: CGPoint(x: c.x + arm, y: c.y))
        context.move(to: CGPoint(x: c.x, y: c.y - arm))
        context.addLine(to: CGPoint(x: c.x, y: c.y + arm))
    }
    context.strokePath()
    context.restoreGState()

    let image = context.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(pixels: points * scale).write(to: output.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: output.appendingPathComponent("Contents.json"))
print("wrote \(images.count) icon images to \(output.path)")
