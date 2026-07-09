#!/usr/bin/env swift
// Renders AppResources/AppIcon.icns: a Big Sur-style squircle with a
// violet gradient and a white waveform glyph. Run from the repo root:
//   swift scripts/generate-app-icon.swift
import AppKit
import CoreGraphics

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        fatalError("no graphics context")
    }

    // Big Sur icon grid: the squircle fills ~80.4% of the canvas.
    let inset = size * 0.098
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let cornerRadius = rect.width * 0.2237
    let squircle = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Soft drop shadow behind the squircle.
    context.saveGState()
    context.addPath(squircle)
    context.setShadow(
        offset: CGSize(width: 0, height: -size * 0.008),
        blur: size * 0.04,
        color: NSColor.black.withAlphaComponent(0.35).cgColor
    )
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    context.restoreGState()

    // Violet gradient fill.
    context.saveGState()
    context.addPath(squircle)
    context.clip()
    let colors = [
        NSColor(calibratedRed: 0.573, green: 0.361, blue: 0.973, alpha: 1).cgColor, // #925CF8
        NSColor(calibratedRed: 0.310, green: 0.153, blue: 0.749, alpha: 1).cgColor  // #4F27BF
    ]
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )

    // Subtle top highlight.
    let highlight = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor.white.withAlphaComponent(0.18).cgColor,
            NSColor.white.withAlphaComponent(0).cgColor
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        highlight,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.midY),
        options: []
    )

    // Waveform glyph: five rounded bars, heights relative to the squircle.
    let barHeights: [CGFloat] = [0.22, 0.40, 0.56, 0.34, 0.18]
    let barWidth = rect.width * 0.072
    let barGap = rect.width * 0.052
    let totalWidth = barWidth * CGFloat(barHeights.count) + barGap * CGFloat(barHeights.count - 1)
    var x = rect.midX - totalWidth / 2
    context.setFillColor(NSColor.white.cgColor)
    context.setShadow(
        offset: .zero,
        blur: size * 0.012,
        color: NSColor.black.withAlphaComponent(0.25).cgColor
    )
    for height in barHeights {
        let barHeight = rect.height * height
        let barRect = CGRect(x: x, y: rect.midY - barHeight / 2, width: barWidth, height: barHeight)
        let bar = CGPath(roundedRect: barRect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)
        context.addPath(bar)
        context.fillPath()
        x += barWidth + barGap
    }
    context.restoreGState()

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, pixels: Int, to url: URL) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let iconsetURL = URL(fileURLWithPath: "AppResources/AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconsetURL)
try! FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let master = drawIcon(size: 1024)
for base in [16, 32, 128, 256, 512] {
    writePNG(master, pixels: base, to: iconsetURL.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(master, pixels: base * 2, to: iconsetURL.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", "AppResources/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
try? FileManager.default.removeItem(at: iconsetURL)
print("AppResources/AppIcon.icns")
