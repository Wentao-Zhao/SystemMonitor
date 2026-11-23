import AppKit
import Foundation

// Original template glyph studies, drawn in an 18-point coordinate space.
// The application implementation is unchanged by this design preview.
struct Mark {
    let path: NSBezierPath
    let svg: String
    var filled = false
    var weight: CGFloat = 1.55
}
struct Glyph {
    let id: String
    let filename: String
    let title: String
    let description: String
    let marks: [Mark]
}

func line(_ coordinates: [(CGFloat, CGFloat)], weight: CGFloat = 1.55) -> Mark {
    let path = NSBezierPath()
    var svg = ""
    for (index, coordinate) in coordinates.enumerated() {
        let p = NSPoint(x: coordinate.0, y: coordinate.1)
        if index == 0 { path.move(to: p); svg += "M \(p.x) \(p.y)" }
        else { path.line(to: p); svg += " L \(p.x) \(p.y)" }
    }
    return Mark(path: path, svg: "<path d=\"\(svg)\"/>", weight: weight)
}
func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat, weight: CGFloat = 1.55) -> Mark {
    Mark(path: NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: radius, yRadius: radius),
         svg: "<rect x=\"\(x)\" y=\"\(y)\" width=\"\(w)\" height=\"\(h)\" rx=\"\(radius)\"/>", weight: weight)
}
func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, filled: Bool = false, weight: CGFloat = 1.55) -> Mark {
    Mark(path: NSBezierPath(ovalIn: NSRect(x: x-r, y: y-r, width: r*2, height: r*2)),
         svg: "<circle cx=\"\(x)\" cy=\"\(y)\" r=\"\(r)\"/>", filled: filled, weight: weight)
}

let gauge = NSBezierPath()
gauge.move(to: NSPoint(x: 3.1, y: 14.1))
gauge.curve(to: NSPoint(x: 1.8, y: 9.3), controlPoint1: NSPoint(x: 2.1, y: 12.8), controlPoint2: NSPoint(x: 1.8, y: 11.1))
gauge.curve(to: NSPoint(x: 9, y: 2.1), controlPoint1: NSPoint(x: 1.8, y: 5.3), controlPoint2: NSPoint(x: 5.0, y: 2.1))
gauge.curve(to: NSPoint(x: 16.2, y: 9.3), controlPoint1: NSPoint(x: 13, y: 2.1), controlPoint2: NSPoint(x: 16.2, y: 5.3))
gauge.curve(to: NSPoint(x: 14.9, y: 14.1), controlPoint1: NSPoint(x: 16.2, y: 11.1), controlPoint2: NSPoint(x: 15.9, y: 12.8))
gauge.close()
let gaugeMark = Mark(path: gauge, svg: "<path d=\"M 3.1 14.1 C 2.1 12.8 1.8 11.1 1.8 9.3 C 1.8 5.3 5 2.1 9 2.1 C 13 2.1 16.2 5.3 16.2 9.3 C 16.2 11.1 15.9 12.8 14.9 14.1 Z\"/>")

var chip = [rounded(4.1, 4.1, 9.8, 9.8, 2, weight: 1.4)]
for n: CGFloat in [7, 11] {
    chip += [line([(n, 1.5), (n, 3.9)], weight: 1.4), line([(n, 14.1), (n, 16.5)], weight: 1.4),
             line([(1.5, n), (3.9, n)], weight: 1.4), line([(14.1, n), (16.5, n)], weight: 1.4)]
}
chip += [line([(7, 10.8), (7, 8.9)], weight: 1.4), line([(9, 10.8), (9, 6.8)], weight: 1.4), line([(11, 10.8), (11, 8.0)], weight: 1.4)]

let glyphs = [
    Glyph(id: "A", filename: "pulse", title: "脉冲", description: "延续 App 的波形图案\n轻巧，识别快", marks: [line([(1.5, 10), (5.0, 10), (7.1, 4.0), (10.2, 14.3), (12.7, 7.1), (14.1, 10), (16.5, 10)], weight: 1.65)]),
    Glyph(id: "B", filename: "gauge", title: "仪表盘", description: "综合监控的含义明确\n适合作为总览入口", marks: [gaugeMark, line([(9, 10.2), (12.5, 6.3)], weight: 1.65), circle(9, 10.2, 1.05, filled: true), line([(5.0, 6.0), (5.6, 6.6)], weight: 1.25)]),
    Glyph(id: "C", filename: "bars", title: "状态柱", description: "三条负载柱，最简洁\n接近原生系统工具", marks: [line([(3.5, 14.5), (3.5, 10.0)], weight: 2.25), line([(9, 14.5), (9, 3.5)], weight: 2.25), line([(14.5, 14.5), (14.5, 7.0)], weight: 2.25)]),
    Glyph(id: "D", filename: "display", title: "监视器", description: "屏幕内嵌状态线\n电脑监控含义最直观", marks: [rounded(1.65, 2.6, 14.7, 10.7, 2.1, weight: 1.35), line([(9, 13.5), (9, 16.0)], weight: 1.35), line([(6.1, 16.0), (11.9, 16.0)], weight: 1.35), line([(4.1, 8.5), (6.3, 8.5), (7.9, 5.9), (10.1, 10.3), (11.7, 7.8), (13.9, 7.8)], weight: 1.2)]),
    Glyph(id: "E", filename: "chip", title: "芯片", description: "芯片轮廓加负载柱\n强调硬件与性能", marks: chip),
    Glyph(id: "F", filename: "status-ring", title: "状态环", description: "圆环包裹状态柱\n紧凑，也更有品牌感", marks: [circle(9, 9, 7.05, weight: 1.35), line([(5.8, 11.7), (5.8, 8.3)], weight: 1.55), line([(9, 11.7), (9, 5.5)], weight: 1.55), line([(12.2, 11.7), (12.2, 7.0)], weight: 1.55)])
]

let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

func image(_ size: NSSize, scale: CGFloat = 2, draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1, y: -1)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}
func write(_ rep: NSBitmapImageRep, _ filename: String) throws {
    try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(filename))
}
func drawGlyph(_ glyph: Glyph, x: CGFloat, y: CGFloat, scale: CGFloat = 1, color: NSColor) {
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext.current!.cgContext
    context.translateBy(x: x, y: y)
    context.scaleBy(x: scale, y: scale)
    color.setStroke(); color.setFill()
    for mark in glyph.marks {
        mark.path.lineWidth = mark.weight
        mark.path.lineCapStyle = .round; mark.path.lineJoinStyle = .round
        if mark.filled { mark.path.fill() } else { mark.path.stroke() }
    }
    NSGraphicsContext.restoreGraphicsState()
}
func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
}
func text(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular, ink: NSColor, mono: Bool = false) {
    NSGraphicsContext.saveGraphicsState()
    let font = mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 4
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph]
    // AppKit text draws upright in a flipped graphics context when given a rect.
    let context = NSGraphicsContext.current!.cgContext
    context.translateBy(x: x, y: y)
    context.scaleBy(x: 1, y: -1)
    let height = (string as NSString).boundingRect(with: NSSize(width: 1000, height: 1000), options: [.usesLineFragmentOrigin], attributes: attributes).height
    (string as NSString).draw(in: NSRect(x: 0, y: -height, width: 1000, height: height), withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
}

for glyph in glyphs {
    for scale: CGFloat in [1, 2, 3] {
        try write(image(NSSize(width: 18, height: 18), scale: scale) {
            drawGlyph(glyph, x: 0, y: 0, color: .black)
        }, "\(glyph.id)-\(glyph.filename)\(scale == 1 ? "" : "@\(Int(scale))x").png")
    }
    let shapes = glyph.marks.map { mark in
        let attrs = mark.filled ? "fill=\"currentColor\" stroke=\"none\"" : "fill=\"none\" stroke=\"currentColor\" stroke-width=\"\(mark.weight)\""
        return "<g \(attrs)>\(mark.svg)</g>"
    }.joined(separator: "\n")
    let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 18 18\" width=\"18\" height=\"18\" stroke-linecap=\"round\" stroke-linejoin=\"round\" role=\"img\" aria-label=\"\(glyph.title)\">\n\(shapes)\n</svg>\n"
    try svg.write(to: directory.appendingPathComponent("\(glyph.id)-\(glyph.filename).svg"), atomically: true, encoding: .utf8)
}

let board = image(NSSize(width: 736, height: 800)) {
    color(0xF4F5F7).setFill(); NSRect(x: 0, y: 0, width: 736, height: 800).fill()
    text("SYSTEMMONITOR / ICON STUDIES", x: 24, y: 19, size: 10, weight: .medium, ink: color(0x747980), mono: true)
    text("菜单栏图标 · 六个方向", x: 24, y: 43, size: 23, weight: .semibold, ink: color(0x1E242A))
    text("单色模板 · 18 pt 参考尺寸 · 深浅背景对比", x: 24, y: 78, size: 11.5, ink: color(0x6F747C))
    for (index, glyph) in glyphs.enumerated() {
        let x = CGFloat(index % 2) * 352 + 24
        let y = CGFloat(index / 2) * 214 + 112
        let card = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 336, height: 198), xRadius: 12, yRadius: 12)
        NSColor.white.setFill(); card.fill()
        color(0xE2E5E9).setStroke(); card.lineWidth = 0.7; card.stroke()
        text("\(glyph.id)   \(glyph.title)", x: x+18, y: y+16, size: 14, weight: .semibold, ink: color(0x20262D))
        if index == 0 { text("推荐", x: x+288, y: y+19, size: 10, weight: .medium, ink: color(0x238571)) }
        drawGlyph(glyph, x: x+26, y: y+58, scale: 3, color: color(0x252A31))
        text(glyph.description, x: x+108, y: y+66, size: 11.5, ink: color(0x737880))
        for dark in [false, true] {
            let sx = x + (dark ? 174 : 18), sy = y+132
            (dark ? color(0x292B30) : color(0xEBEDF0)).setFill()
            NSBezierPath(roundedRect: NSRect(x: sx, y: sy, width: 144, height: 29), xRadius: 6, yRadius: 6).fill()
            let ink = dark ? color(0xF6F7F8) : color(0x272B31)
            drawGlyph(glyph, x: sx+10, y: sy+5.5, color: ink)
            text("24%  ↓1.2M", x: sx+38, y: sy+8, size: 10.5, weight: .medium, ink: ink, mono: true)
            text(dark ? "深色 · 18 pt" : "浅色 · 18 pt", x: sx, y: y+170, size: 9.5, ink: color(0x838991))
        }
    }
    text("放大图看造型，下方小样看菜单栏中的辨识度。", x: 24, y: 770, size: 10.5, ink: color(0x757B83))
}
try write(board, "menu-bar-icon-studies.png")
print(directory.appendingPathComponent("menu-bar-icon-studies.png").path)
