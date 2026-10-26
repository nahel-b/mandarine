// Génère Resources/AppIcon.icns à partir de logo.svg : carré arrondi « squircle » macOS (corps 824/1024), ombre douce.
// Usage : swift Scripts/make_icon.swift
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
guard let svg = NSImage(contentsOf: root.appendingPathComponent("logo.svg")) else { fatalError("logo.svg illisible") }

func icon(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let body = NSRect(x: s * 100 / 1024, y: s * 100 / 1024, width: s * 824 / 1024, height: s * 824 / 1024)
    let path = NSBezierPath(roundedRect: body, xRadius: body.width * 0.2237, yRadius: body.width * 0.2237)   // proportion de l'icône macOS
    NSGraphicsContext.current?.cgContext.saveGState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.30); shadow.shadowBlurRadius = s * 0.02; shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.set()
    NSColor.white.setFill(); path.fill()
    NSGraphicsContext.current?.cgContext.restoreGState()
    path.addClip()
    svg.draw(in: body, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let set = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256),
                   ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    try icon(px).representation(using: .png, properties: [:])!.write(to: set.appendingPathComponent("\(name).png"))
}
print("iconset prêt :", set.path)
