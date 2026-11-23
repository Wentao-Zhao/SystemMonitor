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

func matrix(_ ink: NSColor) {
    let columns = [[("CPU ","24%"),("GPU ","16%")],[("MEM ","62%"),("TMP ","72°")],[("R ","12M/s"),("W ","2.3M/s")],[("↓", "4.8M/s"),("↑", "1.2M/s")],[("FAN ","1.8k"),("PWR ","18W")]]
    for (i, rows) in columns.enumerated() {
        let x = CGFloat(i)*54+7
        pair(rows[0].0, rows[0].1, x, 0.1, ink)
        pair(rows[1].0, rows[1].1, x, 10.9, ink)
        if i < 4 { stroke([(x+48,3),(x+48,19)], ink.withAlphaComponent(0.2), width: 0.5) }
    }
}
func visual(_ ink: NSColor) {
    var x: CGFloat = 6
    label("CPU×10",x,0,7.3,ink.withAlphaComponent(0.80),weight:.medium); coreBars(x,9.5,ink); x += 40
    label("GPU",x,0,7.3,ink.withAlphaComponent(0.80),weight:.medium)
    trend(x,10,26,11,ink,values:[0.10,0.22,0.62,0.31,0.16,0.23,0.11]); x += 34
    label("MEM",x,0,7.3,ink.withAlphaComponent(0.80),weight:.medium)
    for i in 0..<7 { rect(x+CGFloat(i)*2.7, 10, 1.7, 11, ink.withAlphaComponent(i<4 ? 1 : 0.22), radius:0.5) }; x += 27
    label("DISK",x,0,7.3,ink.withAlphaComponent(0.80),weight:.medium)
    trend(x,10,24,4.5,ink,values:[0.1,0.2,0.9,0.1,0.4,0.2]); trend(x,16.5,24,4.5,ink.withAlphaComponent(0.60),values:[0.1,0.4,0.2,0.7,0.3,0.15]); x += 32
    pair("↓","4.8M/s",x,0.1,ink,size:8.1); pair("↑","1.2M/s",x,10.9,ink,size:8.1); x += 45
    for (key,value) in [("TMP","72°"),("FAN","1.8k"),("PWR","18W")] {
        label(key,x,0,7.3,ink.withAlphaComponent(0.80),weight:.medium)
        label(value,x,10,9.0,ink,weight:.semibold,mono:true); x += 29
    }
}
func compact(_ ink: NSColor) {
    label("CPU×10",6,0,7.3,ink.withAlphaComponent(0.80),weight:.medium); coreBars(6,9.5,ink)
    label("GPU",45,0,7.3,ink.withAlphaComponent(0.80),weight:.medium); label("16%",45,10,9,ink,weight:.semibold,mono:true)
    label("MEM",75,0,7.3,ink.withAlphaComponent(0.80),weight:.medium); label("62%",75,10,9,ink,weight:.semibold,mono:true)
    pair("↓","4.8M/s",108,0.1,ink,size:8.2); pair("↑","1.2M/s",108,10.9,ink,size:8.2)
}

let width: CGFloat = 736, height: CGFloat = 846
let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(width*2),pixelsHigh:Int(height*2),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
let cg = NSGraphicsContext.current!.cgContext
cg.scaleBy(x:2,y:2); cg.translateBy(x:0,y:height); cg.scaleBy(x:1,y:-1)
let primary = rgb(0x232930), secondary = rgb(0x777E87)
rect(0,0,width,height,rgb(0xF4F5F7))
label("SYSTEMMONITOR / LIVE STATUS LAYOUTS",24,19,10,secondary,weight:.medium,mono:true)
label("让菜单栏承载更多实时信息",24,43,23,primary,weight:.semibold)
label("三种排法 · 以下为示例读数 · 小样按 22 pt 菜单栏高度设计",24,79,11.5,secondary)

for index in 0..<3 {
    let top = CGFloat(index)*214+112
    let cardHeight: CGFloat = index == 2 ? 228 : 198
    rect(24,top,688,cardHeight,.white,radius:12)
    let outline = NSBezierPath(roundedRect:NSRect(x:24,y:top,width:688,height:cardHeight),xRadius:12,yRadius:12)
    rgb(0xE1E5E9).setStroke(); outline.lineWidth=0.7; outline.stroke()
    let titles = ["A   双行数据矩阵", "B   分组微型仪表", "C   核心指标常驻，其余展开"]
    let descriptions = ["8 类指标 / 10 项读数同时可见 · 宽约 280 pt", "8 类指标 + CPU 10 核负载 · 宽约 280 pt", "CPU / GPU / 内存 / 网速常驻 · 宽约 164 pt"]
    label(titles[index],42,top+16,14,primary,weight:.semibold)
    label(descriptions[index],42,top+41,11.5,secondary)
    if index == 0 { label("推荐",657,top+18,10,rgb(0x238571),weight:.medium) }
    if index < 2 {
        rect(42,top+69,652,54,rgb(0x292B30),radius:7)
        scaled(54,top+74,2) { index == 0 ? matrix(.white) : visual(.white) }
        label("2×",660,top+90,9,rgb(0x9298A1),mono:true)
        rect(42,top+136,652,31,rgb(0xEBEDF0),radius:6)
        scaled(54,top+140.5,1) { index == 0 ? matrix(primary) : visual(primary) }
        label("接近实际尺寸",604,top+145,9,secondary)
        label(index == 0 ? "CPU / GPU / 内存 / 温度 / 磁盘读写 / 网速 / 风扇 / 整机功耗" : "CPU 显示各核心；GPU、内存和磁盘以微图呈现，精确数值悬停查看",42,top+178,10,secondary)
    } else {
        rect(42,top+69,344,54,rgb(0x292B30),radius:7)
        scaled(50,top+74,2) { compact(.white) }
        rect(42,top+137,344,31,rgb(0xEBEDF0),radius:6)
        scaled(50,top+141.5,1) { compact(primary) }
        label("接近实际尺寸",294,top+146,9,secondary)
        label("悬停或点击 →",42,top+186,11,secondary)
        rect(411,top+69,283,142,rgb(0xF4F6F8),radius:9)
        label("完整读数",424,top+80,10.5,primary,weight:.semibold)
        let rows = ["CPU 24%       GPU 16%", "内存 62%      温度 72°C", "磁盘 R12M/s   W2.3M/s", "网络 ↓4.8M/s  ↑1.2M/s", "风扇 1800RPM  整机 18W"]
        for (row,string) in rows.enumerated() { label(string,424,top+101+CGFloat(row)*20,10.3,primary,mono:true) }
    }
}
label("分组可隐藏和重排；温度按 °C、转速按千 RPM、功耗按 W。",24,805,11,secondary)
NSGraphicsContext.restoreGraphicsState()
let output = destination.appendingPathComponent("menu-bar-data-layouts.png")
try bitmap.representation(using:.png,properties:[:])!.write(to:output)
print(output.path)
