#!/usr/bin/env swift
// Draws curly's icon: a rounded square, a gradient, and a pair of braces with
// a terminal prompt. Run as `swift Scripts/make-icon.swift <out.png>`.
//
// Drawing goes into an explicit offscreen bitmap rather than through
// NSImage.lockFocus, so this works on a headless machine such as a CI runner.
import AppKit

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let side = 1024

guard
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: side,
        pixelsHigh: side,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ),
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
else {
    FileHandle.standardError.write(Data("could not make a drawing surface\n".utf8))
    exit(1)
}

let length = CGFloat(side)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

let bounds = NSRect(x: 0, y: 0, width: length, height: length)
let inset = length * 0.08
let shape = NSBezierPath(
    roundedRect: bounds.insetBy(dx: inset, dy: inset),
    xRadius: length * 0.22,
    yRadius: length * 0.22
)

let gradient = NSGradient(
    colors: [
        NSColor(calibratedRed: 0.36, green: 0.44, blue: 0.95, alpha: 1),
        NSColor(calibratedRed: 0.58, green: 0.29, blue: 0.86, alpha: 1),
    ]
)
gradient?.draw(in: shape, angle: -70)

func draw(_ text: String, size: CGFloat, color: NSColor, at point: NSPoint, weight: NSFont.Weight) {
    let font = NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let string = NSAttributedString(string: text, attributes: attributes)
    let measured = string.size()
    string.draw(at: NSPoint(x: point.x - measured.width / 2, y: point.y - measured.height / 2))
}

// The braces say "this is structured text you can edit".
draw("{ }", size: length * 0.40, color: .white, at: NSPoint(x: length / 2, y: length * 0.56), weight: .bold)
// The prompt says "and it ends up in your terminal".
draw(">_", size: length * 0.13, color: NSColor(white: 1, alpha: 0.82),
     at: NSPoint(x: length / 2, y: length * 0.31), weight: .semibold)

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("could not encode the icon\n".utf8))
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: path))
} catch {
    FileHandle.standardError.write(Data("could not write \(path): \(error)\n".utf8))
    exit(1)
}
