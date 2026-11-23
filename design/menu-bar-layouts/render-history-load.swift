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

// Each sample represents two seconds. Both traces share a fixed 0–100% range.
let cpu:[CGFloat]=[0.12,0.10,0.12,0.14,0.25,0.55,0.89,0.64,0.33,0.16,0.18,0.18,0.30,0.60,0.75,0.30,0.15,0.11,0.16,0.22,0.32,0.70,0.49,0.25,0.18,0.22,0.40,0.55,0.36,0.24]
let gpu:[CGFloat]=[0.08,0.07,0.07,0.13,0.13,0.15,0.24,0.50,0.80,0.67,0.23,0.12,0.09,0.12,0.18,0.33,0.41,0.28,0.16,0.12,0.10,0.12,0.18,0.13,0.20,0.16,0.17,0.12,0.16,0.16]
func miniHistory(_ ink:NSColor) {
    label("CPU",0,0.5,6.3,ink.withAlphaComponent(0.64),weight:.medium)
    label("GPU",0,11.3,6.3,ink.withAlphaComponent(0.64),weight:.medium)
    let left:CGFloat=16,w:CGFloat=29
    for (index,values) in [cpu,gpu].enumerated() {
        let top:CGFloat=index==0 ? 1.8 : 12.6
        let h:CGFloat=7.7
        stroke([(left,top+h),(left+w,top+h)],ink.withAlphaComponent(0.13),width:0.4)
        trend(left,top,w,h,ink.withAlphaComponent(index==0 ? 1 : 0.82),values:values)
        let p=NSBezierPath(ovalIn:NSRect(x:left+w-0.65,y:top+h*(1-values.last!)-0.65,width:1.3,height:1.3))
        ink.setFill();p.fill()
    }
    // Memory is a capacity indicator, not a processor-load history.
    rect(53,3,3.2,16,ink.withAlphaComponent(0.14),radius:1.0)
    rect(53,3+16*(1-0.62),3.2,16*0.62,ink,radius:1.0)
    rateArrow(67,3.4,down:true,ink:ink.withAlphaComponent(0.60))
    rateArrow(67,14.2,down:false,ink:ink.withAlphaComponent(0.60))
    rightText("4.8",91.5,0.1,size:9.2,ink:ink)
    rightText("1.2",91.5,10.9,size:9.2,ink:ink)
    label("M",95.5,0.9,8.2,ink.withAlphaComponent(0.68),weight:.medium,mono:true)
    label("M",95.5,11.7,8.2,ink.withAlphaComponent(0.68),weight:.medium,mono:true)
}
let width:CGFloat=736,height:CGFloat=386
let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(width*2),pixelsHigh:Int(height*2),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
let cg=NSGraphicsContext.current!.cgContext
cg.scaleBy(x:2,y:2);cg.translateBy(x:0,y:height);cg.scaleBy(x:1,y:-1)
let primary=rgb(0x232930),secondary=rgb(0x777E87)
rect(0,0,width,height,rgb(0xF4F5F7))
label("负载看趋势，网速读数字",24,20,23,primary,weight:.semibold)
label("CPU / GPU 最近 60 秒 · 内存容量条 · 双行网速 · 以下为设计示例",24,60,11.5,secondary)
rect(24,98,688,178,.white,radius:12)
let outline=NSBezierPath(roundedRect:NSRect(x:24,y:98,width:688,height:178),xRadius:12,yRadius:12)
rgb(0xE1E5E9).setStroke();outline.lineWidth=0.7;outline.stroke()
label("放大看细节",44,113,10,secondary)
rect(44,138,282,67,rgb(0x292B30),radius:8)
scaled(59,144,2.4) {miniHistory(.white)}
label("接近实际尺寸 · 宽约 106 pt",378,113,10,secondary)
rect(378,141,148,34,rgb(0x292B30),radius:6)
scaled(399,147,1) {miniHistory(.white)}
rect(540,141,148,34,rgb(0xEBEDF0),radius:6)
scaled(561,147,1) {miniHistory(primary)}
label("上 CPU / 下 GPU，时间从左向右",44,226,11,primary)
label("独立刻度均为 0–100%，便于比较负载",44,247,10.5,secondary)
label("细条表示内存使用率",378,201,11,primary)
label("下载 / 上传仍用数字，单位随速率变化",378,224,10.5,secondary)
label("最近 60 秒的曲线，能看出尖峰、持续繁忙和负载回落。",24,303,12,primary)
label("温度暂不常驻；精确读数与完整历史在展开面板查看。",24,346,11,secondary)
NSGraphicsContext.restoreGraphicsState()
let output=destination.appendingPathComponent("menu-bar-history-load.png")
try bitmap.representation(using:.png,properties:[:])!.write(to:output)
print(output.path)
