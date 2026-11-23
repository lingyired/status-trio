#!/usr/bin/env swift
// Generates artwork only. Real draggable icons and labels belong to Finder.
import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 1 || arguments.count == 3 && arguments[1] == "--preview" else {
    fputs("Usage: swift scripts/generate-dmg-background.swift OUTPUT_DIR [--preview APP_ICON]\n", stderr)
    exit(2)
}
let directory = URL(fileURLWithPath: arguments[0], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let width = 660
let height = 420
func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}
func render(scale: Int, preview: Bool) throws {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * scale,
        pixelsHigh: height * scale, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot allocate bitmap") }
    bitmap.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    color(0xF5F5F7).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    func text(_ value: String, top: CGFloat, size: CGFloat, weight: NSFont.Weight, ink: UInt32) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color(ink), .paragraphStyle: style
        ]
        let lineHeight = size * 1.6
        (value as NSString).draw(in: NSRect(x: 24, y: CGFloat(height) - top - lineHeight,
            width: CGFloat(width) - 48, height: lineHeight), withAttributes: attributes)
    }
    // Finder's visible content area is shorter than the window: keep every line
    // in the top third so a bottom toolbar or path bar cannot clip it.
    text("将 Status Trio 拖入「应用程序」", top: 40, size: 21, weight: .medium, ink: 0x1D1D1F)
    text("Drag Status Trio into the Applications folder", top: 76, size: 13.5, weight: .regular, ink: 0x66666B)
    text("拖入后即可完成安装，再从应用启动台打开 Status Trio。", top: 112, size: 13.5, weight: .regular, ink: 0x66666B)
    text("Once copied, open Status Trio from Launchpad.", top: 138, size: 12, weight: .regular, ink: 0x66666B)
    color(0x348DE5).setStroke()
    let arrow = NSBezierPath()
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 300, y: 190))
    arrow.line(to: NSPoint(x: 360, y: 190))
    arrow.move(to: NSPoint(x: 347, y: 203))
    arrow.line(to: NSPoint(x: 360, y: 190))
    arrow.line(to: NSPoint(x: 347, y: 177))
    arrow.stroke()
    if preview {
        let icon = NSImage(contentsOfFile: arguments[2])
        icon?.draw(in: NSRect(x: 128, y: 138, width: 104, height: 104))
        NSWorkspace.shared.icon(forFile: "/Applications").draw(in: NSRect(x: 428, y: 138, width: 104, height: 104))
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: color(0x1D1D1F)]
        for (label, x) in [("Status Trio", CGFloat(180)), ("Applications", CGFloat(480))] {
            let value = label as NSString
            let size = value.size(withAttributes: attributes)
            value.draw(at: NSPoint(x: x - size.width / 2, y: 112), withAttributes: attributes)
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode PNG") }
    let name = preview ? "preview.png" : (scale == 1 ? "background.png" : "background@2x.png")
    try png.write(to: directory.appendingPathComponent(name))
}
try render(scale: 1, preview: false)
try render(scale: 2, preview: false)
if arguments.count == 3 { try render(scale: 2, preview: true) }
