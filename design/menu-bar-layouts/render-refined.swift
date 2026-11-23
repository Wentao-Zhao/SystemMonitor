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


func rightText(_ string: String, _ right: CGFloat, _ y: CGFloat, size: CGFloat, ink: NSColor) {
    let font=NSFont.monospacedDigitSystemFont(ofSize:size,weight:.semibold)
    let w=(string as NSString).size(withAttributes:[.font:font]).width
    label(string,right-w,y,size,ink,weight:.semibold,mono:true)
}
func rateArrow(_ x: CGFloat,_ y: CGFloat,down:Bool,ink:NSColor) {
    let tipY=y+(down ? 4.8 : 0),tailY=y+(down ? 0 : 4.8)
    stroke([(x,tailY),(x,tipY)],ink,width:0.85)
    let wingY=tipY+(down ? -1.8 : 1.8)
    stroke([(x-1.7,wingY),(x,tipY),(x+1.7,wingY)],ink,width:0.85)
}
func refined(_ ink:NSColor,loads:[CGFloat]=[0.24,0.16,0.62],download:String="4.8",upload:String="1.2") {
    for (index,value) in loads.enumerated() {
        let x:CGFloat=1+CGFloat(index)*5
        rect(x,4,3,14,ink.withAlphaComponent(0.13),radius:0.9)
        rect(x,4+14*(1-value),3,14*value,ink,radius:0.9)
    }
    rateArrow(23.5,3.4,down:true,ink:ink.withAlphaComponent(0.62))
    rateArrow(23.5,14.2,down:false,ink:ink.withAlphaComponent(0.62))
    rightText(download,49.5,0.1,size:9.2,ink:ink)
    rightText(upload,49.5,10.9,size:9.2,ink:ink)
    label("M",53,0.9,8.2,ink.withAlphaComponent(0.68),weight:.medium,mono:true)
    label("M",53,11.7,8.2,ink.withAlphaComponent(0.68),weight:.medium,mono:true)
}
let width:CGFloat=736,height:CGFloat=386
let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(width*2),pixelsHigh:Int(height*2),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
let cg=NSGraphicsContext.current!.cgContext
cg.scaleBy(x:2,y:2);cg.translateBy(x:0,y:height);cg.scaleBy(x:1,y:-1)
let primary=rgb(0x232930),secondary=rgb(0x777E87)
rect(0,0,width,height,rgb(0xF4F5F7))
label("负载 + 网速 · 精修版",24,20,23,primary,weight:.semibold)
label("约 64 pt · 柱形更轻，数字固定对齐 · 以下为示例读数",24,59,11.5,secondary)
rect(24,96,688,182,.white,radius:12)
let outline=NSBezierPath(roundedRect:NSRect(x:24,y:96,width:688,height:182),xRadius:12,yRadius:12)
rgb(0xE1E5E9).setStroke();outline.lineWidth=0.7;outline.stroke()
label("放大看细节",48,111,10,secondary)
rect(48,135,228,78,rgb(0x292B30),radius:9)
scaled(67,141,3) {refined(.white)}
label("CPU · GPU · 内存",48,232,11,secondary)
label("接近实际尺寸",420,111,10,secondary)
rect(420,139,112,34,rgb(0x292B30),radius:6)
scaled(443,145,1) {refined(.white)}
rect(544,139,112,34,rgb(0xEBEDF0),radius:6)
scaled(567,145,1) {refined(primary)}
label("弱化箭头与单位，优先看清数值",420,194,11,primary)
label("留白分组，去掉竖分割线",420,218,11,secondary)
label("负载升高时，同一结构仍保持清楚",24,299,11.5,secondary)
rect(420,292,112,34,rgb(0x292B30),radius:6)
scaled(443,298,1) {refined(.white,loads:[0.84,0.65,0.78],download:"12.6",upload:"2.3")}
label("精确读数及其它指标，依旧通过展开面板查看。",24,350,11,secondary)
NSGraphicsContext.restoreGraphicsState()
let output=destination.appendingPathComponent("menu-bar-minimal-refined.png")
try bitmap.representation(using:.png,properties:[:])!.write(to:output)
print(output.path)
