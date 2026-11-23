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


// Original native menu-bar studies: a common two-level type scale and 0.85pt ink.
let cpu:[CGFloat]=[0.18,0.18,0.19,0.22,0.30,0.46,0.62,0.73,0.77,0.76,0.72,0.63,0.53,0.39,0.32,0.29,0.33,0.40,0.47,0.51,0.49,0.43,0.37,0.32,0.29,0.27,0.26,0.25,0.24,0.24]
let gpu:[CGFloat]=[0.08,0.09,0.08,0.08,0.09,0.10,0.16,0.30,0.48,0.60,0.65,0.66,0.62,0.56,0.46,0.33,0.23,0.18,0.15,0.14,0.15,0.17,0.20,0.24,0.29,0.30,0.28,0.24,0.20,0.16]
func pathFor(_ values:[CGFloat],x:CGFloat,y:CGFloat,w:CGFloat,h:CGFloat) -> NSBezierPath {
    let path=NSBezierPath()
    for (i,value) in values.enumerated() {
        let point=NSPoint(x:x+CGFloat(i)*w/CGFloat(values.count-1),y:y+h*(1-value))
        if i==0 {path.move(to:point)} else {path.line(to:point)}
    }
    return path
}
func history(_ values:[CGFloat],_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat,_ ink:NSColor,dashed:Bool=false) {
    let path=pathFor(values,x:x,y:y,w:w,h:h)
    path.lineWidth=0.85;path.lineCapStyle = .round;path.lineJoinStyle = .round
    if dashed {path.setLineDash([1.8,1.6],count:2,phase:0)}
    ink.setStroke();path.stroke()
}
func textRight(_ string:String,_ right:CGFloat,_ y:CGFloat,_ size:CGFloat,_ ink:NSColor,weight:NSFont.Weight = .medium) {
    let font=NSFont.monospacedDigitSystemFont(ofSize:size,weight:weight)
    let width=(string as NSString).size(withAttributes:[.font:font]).width
    label(string,right-width,y,size,ink,weight:weight,mono:true)
}
func rate(_ value:String,_ unit:String,_ right:CGFloat,_ y:CGFloat,_ ink:NSColor,size:CGFloat=8.5) {
    let nf=NSFont.monospacedDigitSystemFont(ofSize:size,weight:.medium)
    let uf=NSFont.systemFont(ofSize:size-0.5,weight:.regular)
    let result=NSMutableAttributedString(string:value,attributes:[.font:nf,.foregroundColor:ink])
    result.append(NSAttributedString(string:unit,attributes:[.font:uf,.foregroundColor:ink.withAlphaComponent(0.62)]))
    let bounds=result.size()
    NSGraphicsContext.saveGraphicsState()
    let cg=NSGraphicsContext.current!.cgContext
    cg.translateBy(x:right-bounds.width,y:y);cg.scaleBy(x:1,y:-1)
    result.draw(in:NSRect(x:0,y:-bounds.height,width:bounds.width+1,height:bounds.height))
    NSGraphicsContext.restoreGraphicsState()
}
func arrow(_ x:CGFloat,_ y:CGFloat,down:Bool,_ ink:NSColor) {
    let tip=y+(down ? 4.5 : 0),tail=y+(down ? 0 : 4.5),wing=tip+(down ? -1.6 : 1.6)
    stroke([(x,tail),(x,tip)],ink,width:0.75)
    stroke([(x-1.5,wing),(x,tip),(x+1.5,wing)],ink,width:0.75)
}
func memory(_ x:CGFloat,_ w:CGFloat,_ ink:NSColor) {
    textRight("62%",x+w-1,0.2,8.5,ink)
    rect(x,15.0,w,2.4,ink.withAlphaComponent(0.15),radius:1.2)
    rect(x,15.0,w*0.62,2.4,ink.withAlphaComponent(0.92),radius:1.2)
}


func occupancyRing(_ x:CGFloat,_ y:CGFloat,_ fraction:CGFloat,_ ink:NSColor,_ accent:NSColor) {
    let radius:CGFloat=6.3
    let track=NSBezierPath(ovalIn:NSRect(x:x-radius,y:y-radius,width:radius*2,height:radius*2))
    ink.withAlphaComponent(0.15).setStroke();track.lineWidth=1.65;track.stroke()
    let points=(0...64).map { i -> (CGFloat,CGFloat) in
        let angle=(-90+360*fraction*CGFloat(i)/64)*CGFloat.pi/180
        return (x+radius*cos(angle),y+radius*sin(angle))
    }
    stroke(points,accent,width:1.65)
}
func memoryColor(_ state:Int,_ dark:Bool) -> NSColor {
    if state==1 {return rgb(dark ? 0xF4C35C : 0xAA6A10)}
    if state==2 {return rgb(dark ? 0xF38080 : 0xB53647)}
    return rgb(dark ? 0x63D39A : 0x18825C)
}
func coloredStatus(_ ink:NSColor,dark:Bool) {
    stroke([(1,19),(37,19)],ink.withAlphaComponent(0.12),width:0.35)
    history(cpu,1,3,36,16,ink.withAlphaComponent(0.94))
    occupancyRing(52.5,11,0.62,ink,memoryColor(0,dark))
    arrow(71,3.3,down:true,ink.withAlphaComponent(0.62))
    arrow(71,14.1,down:false,ink.withAlphaComponent(0.62))
    rate("4.8","M",98,0.1,ink)
    rate("1.2","M",98,10.9,ink)
}
let width:CGFloat=736,height:CGFloat=398
let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(width*2),pixelsHigh:Int(height*2),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
let cg=NSGraphicsContext.current!.cgContext
cg.scaleBy(x:2,y:2);cg.translateBy(x:0,y:height);cg.scaleBy(x:1,y:-1)
let primary=rgb(0x242A31),secondary=rgb(0x787F88)
rect(0,0,width,height,rgb(0xF4F5F7))
label("内存改用彩色占用环",24,20,23,primary,weight:.semibold)
label("常驻看占比和状态，精确读数放进悬停详情 · 以下为设计示例",24,60,11.5,secondary)
rect(24,98,688,168,.white,radius:12)
let outline=NSBezierPath(roundedRect:NSRect(x:24,y:98,width:688,height:168),xRadius:12,yRadius:12)
rgb(0xE2E6EA).setStroke();outline.lineWidth=0.7;outline.stroke()
label("放大看结构",44,113,10,secondary)
rect(44,138,282,65,rgb(0x292B30),radius:7)
scaled(62,144,2.4) {coloredStatus(.white,dark:true)}
label("实际尺寸 · 约 102 pt",378,113,10,secondary)
rect(378,142,148,32,rgb(0x292B30),radius:5)
scaled(401,147,1) {coloredStatus(.white,dark:true)}
rect(540,142,148,32,rgb(0xEBEDF0),radius:5)
scaled(563,147,1) {coloredStatus(primary,dark:false)}
label("CPU 历史曲线 · 彩色内存环 · 上下行网速",44,226,11,secondary)
label("弧长 = 已用比例",378,199,11,primary)
label("颜色 = 系统内存压力",378,222,11,secondary)
let titles=["正常","压力升高","内存紧张"]
let fractions:[CGFloat]=[0.62,0.80,0.94]
for index in 0..<3 {
    let x:CGFloat=24+CGFloat(index)*234
    occupancyRing(x+11,307,fractions[index],primary,memoryColor(index,false))
    label(titles[index],x+30,300,11,primary)
}
label("内存的百分比、已用容量和总量，在悬停详情中查看。",24,356,11,secondary)
NSGraphicsContext.restoreGraphicsState()
let output=destination.appendingPathComponent("menu-bar-colored-memory.png")
try bitmap.representation(using:.png,properties:[:])!.write(to:output)
print(output.path)
