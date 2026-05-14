#!/usr/bin/env swift
// Renders Assets/AppIcon.iconset from the `square.stack.3d.up` SF Symbol and
// runs `iconutil` to produce ClaudeMDSwitcher.app/Contents/Resources/AppIcon.icns.
// Idempotent. Called from build.sh and release.sh after the .app skeleton is
// laid out but before signing.
//
// If NSImage(systemSymbolName:) returns nil (the AppKit runtime didn't come
// up fully under a non-foreground process), the script exits 1 with a clear
// message rather than silently producing a placeholder.

import Foundation
import AppKit

// Apple's standard 10-entry iconset. Each tuple is (point size, scale, filename).
let entries: [(pt: Int, scale: Int, name: String)] = [
    (16, 1, "icon_16x16.png"),
    (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"),
    (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (512, 2, "icon_512x512@2x.png"),
]

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = cwd.appendingPathComponent("Assets/AppIcon.iconset")
let icnsOut = cwd.appendingPathComponent("ClaudeMDSwitcher.app/Contents/Resources/AppIcon.icns")

try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

guard let symbol = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: nil) else {
    FileHandle.standardError.write(Data("generate_icon: NSImage(systemSymbolName:) returned nil\n".utf8))
    exit(1)
}

let tint = NSColor.systemBlue.withAlphaComponent(0.9)

func render(pixelSize: Int) -> Data {
    let size = NSSize(width: pixelSize, height: pixelSize)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = size

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.setFill()
    NSRect(origin: .zero, size: size).fill()

    // Symbol fills ~70% of canvas, centered.
    let glyphSide = CGFloat(pixelSize) * 0.70
    let cfg = NSImage.SymbolConfiguration(pointSize: glyphSide, weight: .regular)
    let configured = symbol.withSymbolConfiguration(cfg) ?? symbol

    // Tint by drawing the symbol as a template into a tinted layer.
    configured.isTemplate = true
    let drawSize = configured.size
    let scale = min(glyphSide / drawSize.width, glyphSide / drawSize.height)
    let drawW = drawSize.width * scale
    let drawH = drawSize.height * scale
    let origin = NSPoint(x: (CGFloat(pixelSize) - drawW) / 2, y: (CGFloat(pixelSize) - drawH) / 2)
    let drawRect = NSRect(origin: origin, size: NSSize(width: drawW, height: drawH))

    tint.set()
    configured.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    // Multiply the tint colour over the alpha mask of the rendered symbol.
    NSRect(origin: .zero, size: size).fill(using: .sourceIn)
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("generate_icon: PNG encode failed at \(pixelSize)px\n".utf8))
        exit(1)
    }
    return png
}

for entry in entries {
    let pixels = entry.pt * entry.scale
    let data = render(pixelSize: pixels)
    let url = iconset.appendingPathComponent(entry.name)
    try data.write(to: url)
}

// iconutil to produce the .icns.
try? fm.createDirectory(at: icnsOut.deletingLastPathComponent(), withIntermediateDirectories: true)
let proc = Process()
proc.launchPath = "/usr/bin/iconutil"
proc.arguments = ["-c", "icns", iconset.path, "-o", icnsOut.path]
try proc.run()
proc.waitUntilExit()
if proc.terminationStatus != 0 {
    FileHandle.standardError.write(Data("iconutil failed with exit \(proc.terminationStatus)\n".utf8))
    exit(1)
}

let attrs = try fm.attributesOfItem(atPath: icnsOut.path)
let bytes = (attrs[.size] as? Int) ?? 0
print("Generated AppIcon.icns (\(bytes) bytes)")
