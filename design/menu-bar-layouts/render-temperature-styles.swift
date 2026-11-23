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


func baseLoads(_ ink:NSColor) {
    for (index,value) in ([0.24,0.16,0.62] as [CGFloat]).enumerated() {
        let x:CGFloat=1+CGFloat(index)*5
        rect(x,4,3,14,ink.withAlphaComponent(0.13),radius:0.9)
        rect(x,4+14*(1-value),3,14*value,ink,radius:0.9)
    }
}
func disk(_ x:CGFloat,_ y:CGFloat,_ radius:CGFloat,_ ink:NSColor) {
    ink.setFill();NSBezierPath(ovalIn:NSRect(x:x-radius,y:y-radius,width:radius*2,height:radius*2)).fill()
}
func numericNetwork(_ ink:NSColor,offset:CGFloat=0) {
    rateArrow(52+offset,3.4,down:true,ink:ink.withAlphaComponent(0.60))
    rateArrow(52+offset,14.2,down:false,ink:ink.withAlphaComponent(0.60))
    rightText("4.8",80+offset,0.1,size:9.2,ink:ink)
    rightText("1.2",80+offset,10.9,size:9.2,ink:ink)
    label("M",84+offset,0.9,8.2,ink.withAlphaComponent(0.68),weight:.medium,mono:true)
    label("M",84+offset,11.7,8.2,ink.withAlphaComponent(0.68),weight:.medium,mono:true)
}
func temperatureTicks(_ ink:NSColor) {
    rightText("72°",43,0.7,size:11.2,ink:ink)
    for i in 0..<7 { rect(23+CGFloat(i)*3,18,2,2,ink.withAlphaComponent(i<4 ? 0.9 : 0.18),radius:0.6) }
}
func thermometer(_ ink:NSColor) {
    let p=NSBezierPath()
    p.move(to:NSPoint(x:24,y:13.4));p.line(to:NSPoint(x:24,y:4.5))
    p.curve(to:NSPoint(x:27,y:4.5),controlPoint1:NSPoint(x:24,y:2.5),controlPoint2:NSPoint(x:27,y:2.5))
    p.line(to:NSPoint(x:27,y:13.4))
    p.curve(to:NSPoint(x:29,y:16.5),controlPoint1:NSPoint(x:28.4,y:14.1),controlPoint2:NSPoint(x:29,y:15.1))
    p.curve(to:NSPoint(x:25.5,y:20),controlPoint1:NSPoint(x:29,y:18.5),controlPoint2:NSPoint(x:27.5,y:20))
    p.curve(to:NSPoint(x:22,y:16.5),controlPoint1:NSPoint(x:23.5,y:20),controlPoint2:NSPoint(x:22,y:18.5))
    p.curve(to:NSPoint(x:24,y:13.4),controlPoint1:NSPoint(x:22,y:15.1),controlPoint2:NSPoint(x:22.6,y:14.1));p.close()
    ink.setStroke();p.lineWidth=0.95;p.stroke()
    disk(25.5,16.5,1.55,ink)
    stroke([(25.5,16.3),(25.5,9.7)],ink,width:1.25)
    for y:CGFloat in [5.5,8.5,11.5] {stroke([(29.2,y),(30.7,y)],ink.withAlphaComponent(0.48),width:0.7)}
    rightText("72°",57,4.1,size:11.2,ink:ink)
}
func temperatureArc(_ ink:NSColor) {
    func arc(_ end:CGFloat,_ color:NSColor) {
        let samples=48
        stroke((0...samples).map { i in
            let angle=(135+(end-135)*CGFloat(i)/CGFloat(samples))*CGFloat.pi/180
            return (30+8*cos(angle),11+8*sin(angle))
        },color,width:1.3)
    }
    arc(405,ink.withAlphaComponent(0.18));arc(135+270*0.525,ink)
    rightText("72",34.7,6.1,size:7.8,ink:ink)
    let degree=NSBezierPath(ovalIn:NSRect(x:40.0,y:2.4,width:1.8,height:1.8))
    ink.setStroke();degree.lineWidth=0.65;degree.stroke()
}
func status(_ style:Int,_ ink:NSColor) {
    baseLoads(ink)
    if style==0 {temperatureTicks(ink);numericNetwork(ink)}
    else if style==1 {thermometer(ink);numericNetwork(ink,offset:14)}
    else {temperatureArc(ink);numericNetwork(ink)}
}
let width:CGFloat=736,height:CGFloat=638
let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(width*2),pixelsHigh:Int(height*2),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
let cg=NSGraphicsContext.current!.cgContext
cg.scaleBy(x:2,y:2);cg.translateBy(x:0,y:height);cg.scaleBy(x:1,y:-1)
let primary=rgb(0x232930),secondary=rgb(0x777E87)
rect(0,0,width,height,rgb(0xF4F5F7))
label("温度做成一个小组件",24,20,23,primary,weight:.semibold)
label("网速固定为双行数字 · 温度三种造型 · 以下为示例读数",24,60,11.5,secondary)
let titles=["A   刻度温标","B   细线温度计","C   环形温标"]
let notes=["温度值下配七段刻度，兼顾读数和热度感知。","纤细温度计搭配数字，温度含义最明确。","温度嵌入圆弧，造型更紧凑，数字也相对更小。"]
for index in 0..<3 {
    let top:CGFloat=102+CGFloat(index)*164
    rect(24,top,688,148,.white,radius:12)
    let outline=NSBezierPath(roundedRect:NSRect(x:24,y:top,width:688,height:148),xRadius:12,yRadius:12)
    rgb(0xE1E5E9).setStroke();outline.lineWidth=0.7;outline.stroke()
    label(titles[index],42,top+14,14,primary,weight:.semibold)
    if index==0 {label("推荐",650,top+17,10,rgb(0x238571),weight:.medium)}
    rect(42,top+49,282,56,rgb(0x292B30),radius:8)
    scaled(59,top+53,2.2) {status(index,.white)}
    label("接近实际尺寸",378,top+29,10,secondary)
    rect(378,top+54,148,34,rgb(0x292B30),radius:6)
    rect(540,top+54,148,34,rgb(0xEBEDF0),radius:6)
    let w:CGFloat=index==1 ? 106 : 92
    scaled(378+(148-w)/2,top+60,1) {status(index,.white)}
    scaled(540+(148-w)/2,top+60,1) {status(index,primary)}
    label(notes[index],42,top+121,10.5,secondary)
}
label("从左到右：CPU / GPU / 内存负载 · CPU 温度 · 下载 / 上传；M 表示 MB/s。",24,606,10.5,secondary)
NSGraphicsContext.restoreGraphicsState()
let output=destination.appendingPathComponent("menu-bar-temperature-styles.png")
try bitmap.representation(using:.png,properties:[:])!.write(to:output)
print(output.path)
