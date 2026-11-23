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

func loadAndTemperature(_ ink:NSColor) {
    let loads:[CGFloat]=[0.24,0.16,0.62]
    for (index,value) in loads.enumerated() {
        let x:CGFloat=1+CGFloat(index)*5
        rect(x,4,3,14,ink.withAlphaComponent(0.13),radius:0.9)
        rect(x,4+14*(1-value),3,14*value,ink,radius:0.9)
    }
    rightText("72°",43,4.1,size:11.2,ink:ink)
}
func numericRates(_ ink:NSColor) {
    loadAndTemperature(ink)
    rateArrow(50,3.4,down:true,ink:ink.withAlphaComponent(0.60))
    rateArrow(50,14.2,down:false,ink:ink.withAlphaComponent(0.60))
    rightText("4.8",78,0.1,size:9.2,ink:ink)
    rightText("1.2",78,10.9,size:9.2,ink:ink)
    label("M",82,0.9,8.2,ink.withAlphaComponent(0.68),weight:.medium,mono:true)
    label("M",82,11.7,8.2,ink.withAlphaComponent(0.68),weight:.medium,mono:true)
}
func graphRates(_ ink:NSColor) {
    loadAndTemperature(ink)
    rateArrow(50,3.4,down:true,ink:ink.withAlphaComponent(0.60))
    rateArrow(50,14.2,down:false,ink:ink.withAlphaComponent(0.60))
    trend(56,2,22,7,ink,values:[1/12,2.5/12,7.5/12,1,5/12,2/12,4.8/12])
    trend(56,13,22,7,ink.withAlphaComponent(0.65),values:[0.3/12,0.8/12,0.4/12,2.5/12,4/12,0.4/12,1.2/12])
    rightText("4.8",104,0.1,size:9.2,ink:ink)
    rightText("1.2",104,10.9,size:9.2,ink:ink)
    label("M",108,0.9,8.2,ink.withAlphaComponent(0.68),weight:.medium,mono:true)
    label("M",108,11.7,8.2,ink.withAlphaComponent(0.68),weight:.medium,mono:true)
}
let width:CGFloat=736,height:CGFloat=530
let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(width*2),pixelsHigh:Int(height*2),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
let cg=NSGraphicsContext.current!.cgContext
cg.scaleBy(x:2,y:2);cg.translateBy(x:0,y:height);cg.scaleBy(x:1,y:-1)
let primary=rgb(0x232930),secondary=rgb(0x777E87)
rect(0,0,width,height,rgb(0xF4F5F7))
label("加上温度，网速这样排",24,20,23,primary,weight:.semibold)
label("三根负载柱 + CPU 温度 · 上排下载，下排上传 · 以下为示例读数",24,60,11.5,secondary)
for index in 0..<2 {
    let top:CGFloat=102+CGFloat(index)*193
    rect(24,top,688,176,.white,radius:12)
    let outline=NSBezierPath(roundedRect:NSRect(x:24,y:top,width:688,height:176),xRadius:12,yRadius:12)
    rgb(0xE1E5E9).setStroke();outline.lineWidth=0.7;outline.stroke()
    label(index==0 ? "A   温度 + 紧凑数字" : "B   温度 + 微图与数字",42,top+15,14,primary,weight:.semibold)
    label(index==0 ? "约 92 pt · 温度居中，网速固定对齐" : "约 120 pt · 增加短时趋势，数字保留当前速度",42,top+41,11.5,secondary)
    if index==0 { label("建议默认",642,top+18,10,rgb(0x238571),weight:.medium) }
    rect(42,top+67,282,61,rgb(0x292B30),radius:8)
    scaled(59,top+73,2.2) { index==0 ? numericRates(.white) : graphRates(.white) }
    label("接近实际尺寸",378,top+47,10,secondary)
    rect(378,top+72,148,34,rgb(0x292B30),radius:6)
    rect(540,top+72,148,34,rgb(0xEBEDF0),radius:6)
    let widgetWidth:CGFloat=index==0 ? 92 : 120
    scaled(378+(148-widgetWidth)/2,top+78,1) { index==0 ? numericRates(.white) : graphRates(.white) }
    scaled(540+(148-widgetWidth)/2,top+78,1) { index==0 ? numericRates(primary) : graphRates(primary) }
    label(index==0 ? "优先看数值，占用更少空间。" : "先扫流量有没有波动，再读当前网速。",42,top+145,11,secondary)
}
label("温度默认 CPU，可切换 GPU；示例 M 表示 MB/s，速率单位随大小自动变化。",24,495,10.5,secondary)
NSGraphicsContext.restoreGraphicsState()
let output=destination.appendingPathComponent("menu-bar-temperature-network.png")
try bitmap.representation(using:.png,properties:[:])!.write(to:output)
print(output.path)
