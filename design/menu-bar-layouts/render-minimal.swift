import AppKit
import Foundation

// Menu-bar information layout studies. All displayed readings are examples.
let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
func rgb(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255)/255, green: CGFloat((hex >> 8) & 255)/255, blue: CGFloat(hex & 255)/255, alpha: 1)
}
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor, radius: CGFloat = 0) {
    color.setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: radius, yRadius: radius).fill()
}
func label(_ text: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ color: NSColor, weight: NSFont.Weight = .regular, mono: Bool = false) {
    let font = mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let h = (text as NSString).size(withAttributes: attributes).height
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext.current!.cgContext
    context.translateBy(x: x, y: y); context.scaleBy(x: 1, y: -1)
    (text as NSString).draw(in: NSRect(x: 0, y: -h, width: 1200, height: h), withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
}
func scaled(_ x: CGFloat, _ y: CGFloat, _ factor: CGFloat, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext.current!.cgContext
    context.translateBy(x: x, y: y); context.scaleBy(x: factor, y: factor)
    body(); NSGraphicsContext.restoreGraphicsState()
}
func stroke(_ points: [(CGFloat, CGFloat)], _ ink: NSColor, width: CGFloat = 1) {
    guard let first = points.first else { return }
    ink.setStroke()
    let p = NSBezierPath(); p.move(to: NSPoint(x: first.0, y: first.1))
    for point in points.dropFirst() { p.line(to: NSPoint(x: point.0, y: point.1)) }
    p.lineWidth = width; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke()
}
func coreBars(_ x: CGFloat, _ y: CGFloat, _ ink: NSColor) {
    let values: [CGFloat] = [0.62,0.71,0.24,0.08,0.42,0.17,0.32,0.13,0.07,0.21]
    for (i, value) in values.enumerated() {
        rect(x+CGFloat(i)*3.1, y, 2, 12, ink.withAlphaComponent(0.14), radius: 0.65)
        rect(x+CGFloat(i)*3.1, y+12*(1-value), 2, 12*value, ink.withAlphaComponent(i < 2 ? 0.65 : 1), radius: 0.65)
    }
}
func trend(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ ink: NSColor, values: [CGFloat]) {
    stroke(values.enumerated().map { (x+CGFloat($0.offset)*w/CGFloat(values.count-1), y+h*(1-$0.element)) }, ink, width: 0.95)
}
func pair(_ key: String, _ value: String, _ x: CGFloat, _ y: CGFloat, _ ink: NSColor, size: CGFloat = 8.8) {
    label(key, x, y, size, ink.withAlphaComponent(0.70), weight: .medium, mono: true)
    let prefixWidth = (key as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)]).width
    label(value, x+prefixWidth, y, size, ink, weight: .semibold, mono: true)
}


func minimal(_ ink: NSColor) {
    let loads: [CGFloat] = [0.24,0.16,0.62]
    for (index,load) in loads.enumerated() {
        let x=CGFloat(index)*6
        rect(x,2,3.4,18,ink.withAlphaComponent(0.18),radius:1.3)
        rect(x,2+18*(1-load),3.4,18*load,ink,radius:1.3)
    }
    stroke([(22,4),(22,18)],ink.withAlphaComponent(0.25),width:0.5)
    label("↓4.8M",29,0,9.1,ink,weight:.medium,mono:true)
    label("↑1.2M",29,11,9.1,ink,weight:.medium,mono:true)
}
let width: CGFloat=736, height: CGFloat=320
let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(width*2),pixelsHigh:Int(height*2),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
let cg=NSGraphicsContext.current!.cgContext
cg.scaleBy(x:2,y:2); cg.translateBy(x:0,y:height); cg.scaleBy(x:1,y:-1)
let primary=rgb(0x232930), secondary=rgb(0x777E87)
rect(0,0,width,height,rgb(0xF4F5F7))
label("精简为「负载 + 网速」",24,20,23,primary,weight:.semibold)
label("常驻约 72 pt · 三根负载柱 + 双行网速 · 以下为示例读数",24,59,11.5,secondary)
rect(24,96,688,152,.white,radius:12)
let outline=NSBezierPath(roundedRect:NSRect(x:24,y:96,width:688,height:152),xRadius:12,yRadius:12)
rgb(0xE1E5E9).setStroke(); outline.lineWidth=0.7; outline.stroke()
label("放大看结构",48,111,10,secondary)
rect(48,132,228,72,rgb(0x292B30),radius:9)
scaled(68,139,2.6) { minimal(.white) }
label("三根柱：CPU · GPU · 内存",48,218,11,secondary)
label("接近实际尺寸",430,111,10,secondary)
rect(430,136,112,34,rgb(0x292B30),radius:6)
scaled(447,142,1) { minimal(.white) }
rect(554,136,112,34,rgb(0xEBEDF0),radius:6)
scaled(571,142,1) { minimal(primary) }
label("平时扫一眼负载和网速",430,190,12,primary)
label("需要数值时再展开",430,212,11,secondary)
label("温度、风扇、功耗、磁盘等完整信息保留在展开面板。",24,279,11.5,secondary)
NSGraphicsContext.restoreGraphicsState()
let output=destination.appendingPathComponent("menu-bar-minimal.png")
try bitmap.representation(using:.png,properties:[:])!.write(to:output)
print(output.path)
