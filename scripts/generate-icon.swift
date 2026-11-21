import AppKit
import Foundation

let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(size) / 1024
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: scale, y: scale)
    let shape = NSBezierPath(roundedRect: NSRect(x: 55, y: 55, width: 914, height: 914), xRadius: 205, yRadius: 205)
    NSGradient(starting: NSColor(calibratedRed: 0.12, green: 0.19, blue: 0.30, alpha: 1), ending: NSColor(calibratedRed: 0.035, green: 0.065, blue: 0.12, alpha: 1))!.draw(in: shape, angle: -80)
    NSColor(calibratedWhite: 1, alpha: 0.07).setStroke()
    for y in [320, 512, 704] {
        let line = NSBezierPath(); line.lineWidth = 2
        line.move(to: NSPoint(x: 170, y: y)); line.line(to: NSPoint(x: 854, y: y)); line.stroke()
    }
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 170, y: 465))
    for (x, y) in [(305,465),(386,660),(486,270),(595,758),(678,465),(854,465)] { path.line(to: NSPoint(x: x, y: y)) }
    path.lineJoinStyle = .round; path.lineCapStyle = .round
    NSColor(calibratedRed: 0.24, green: 0.68, blue: 1, alpha: 0.15).setStroke(); path.lineWidth = 62; path.stroke()
    NSColor(calibratedRed: 0.36, green: 0.79, blue: 1, alpha: 1).setStroke(); path.lineWidth = 30; path.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let png = rep.representation(using: .png, properties: [:])!
    let name: String
    switch size {
    case 16: name = "icon_16x16.png"
    case 32: name = "icon_16x16@2x.png"
    case 64: name = "icon_32x32@2x.png"
    case 128: name = "icon_128x128.png"
    case 256: name = "icon_128x128@2x.png"
    case 512: name = "icon_256x256@2x.png"
    default: name = "icon_512x512@2x.png"
    }
    try png.write(to: URL(fileURLWithPath: output).appendingPathComponent(name))
    if [32, 256, 512].contains(size) {
        try png.write(to: URL(fileURLWithPath: output).appendingPathComponent("icon_\(size)x\(size).png"))
    }
}

// ICNS is a sequence of typed PNG chunks. Build it directly so packaging also
// works where iconutil's image-conversion service is unavailable in a sandbox.
if CommandLine.arguments.count > 2 {
    var chunks = Data()
    func bigEndian(_ value: UInt32) -> Data {
        var number = value.bigEndian
        return withUnsafeBytes(of: &number) { Data($0) }
    }
    for (kind, filename) in [("icp4", "icon_16x16.png"), ("ic11", "icon_16x16@2x.png"), ("icp5", "icon_32x32.png"), ("ic12", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"), ("ic13", "icon_128x128@2x.png"), ("ic08", "icon_256x256.png"), ("ic14", "icon_256x256@2x.png"), ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png")] {
        let payload = try Data(contentsOf: URL(fileURLWithPath: output).appendingPathComponent(filename))
        chunks.append(contentsOf: kind.utf8); chunks.append(bigEndian(UInt32(payload.count + 8))); chunks.append(payload)
    }
    var icon = Data("icns".utf8)
    icon.append(bigEndian(UInt32(chunks.count + 8))); icon.append(chunks)
    try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
