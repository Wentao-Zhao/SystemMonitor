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


func cpuHistory(_ ink:NSColor) {
    stroke([(1,19),(37,19)],ink.withAlphaComponent(0.13),width:0.35)
    history(cpu,1,3,36,16,ink.withAlphaComponent(0.94))
}
func dimmMemory(_ ink:NSColor) {
    let outline=NSBezierPath(roundedRect:NSRect(x:47,y:6,width:16,height:8.5),xRadius:1.2,yRadius:1.2)
    ink.withAlphaComponent(0.85).setStroke();outline.lineWidth=0.85;outline.stroke()
    for x:CGFloat in [49.5,52,54.5,57,59.5] {stroke([(x,14.8),(x,17)],ink.withAlphaComponent(0.75),width:0.7)}
    rect(49,8,12,4.5,ink.withAlphaComponent(0.12),radius:0.55)
    rect(49,8,12*0.62,4.5,ink.withAlphaComponent(0.92),radius:0.55)
    textRight("62%",86,5.2,8.8,ink)
}
func ringMemory(_ ink:NSColor) {
    func arc(_ end:CGFloat,_ color:NSColor) {
        let points=(0...64).map { i -> (CGFloat,CGFloat) in
            let angle=(-90+(end+90)*CGFloat(i)/64)*CGFloat.pi/180
            return (54+6.8*cos(angle),11+6.8*sin(angle))
        }
        stroke(points,color,width:1.15)
    }
    arc(270,ink.withAlphaComponent(0.15))
    arc(-90+360*0.62,ink.withAlphaComponent(0.92))
    textRight("62%",86,5.2,8.8,ink)
}
func capacityMemory(_ ink:NSColor) {
    rate("19.8","G",76,0.1,ink,size:8.5)
    rate("/32","G",76,10.9,ink.withAlphaComponent(0.62),size:8.5)
}
func cpuMemoryNetwork(_ index:Int,_ ink:NSColor) {
    cpuHistory(ink)
    if index==0 {dimmMemory(ink)} else if index==1 {ringMemory(ink)} else {capacityMemory(ink)}
    let delta:CGFloat=index==2 ? -10 : 0
    arrow(98+delta,3.3,down:true,ink.withAlphaComponent(0.62))
    arrow(98+delta,14.1,down:false,ink.withAlphaComponent(0.62))
    rate("4.8","M",124+delta,0.1,ink)
    rate("1.2","M",124+delta,10.9,ink)
}
let widths:[CGFloat]=[128,128,118]
let names=["A   内存条","B   占用环","C   已用 / 总量"]
let notes=["内存条轮廓内显示占用，旁边保留百分比，含义更直观。","圆环表达已用比例，百分比保持在外侧，便于读数。","上排已用容量，下排总容量；和网速共用双行数字结构。"]
let width:CGFloat=736,height:CGFloat=650
let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(width*2),pixelsHigh:Int(height*2),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
let cg=NSGraphicsContext.current!.cgContext
cg.scaleBy(x:2,y:2);cg.translateBy(x:0,y:height);cg.scaleBy(x:1,y:-1)
let primary=rgb(0x242A31),secondary=rgb(0x787F88)
rect(0,0,width,height,rgb(0xF4F5F7))
label("CPU 趋势 + 内存 + 网速",24,20,23,primary,weight:.semibold)
label("CPU 保留最近 60 秒历史，内存重新设计 · 以下为示例读数",24,60,11.5,secondary)
for index in 0..<3 {
    let top:CGFloat=102+CGFloat(index)*164
    rect(24,top,688,148,.white,radius:12)
    let outline=NSBezierPath(roundedRect:NSRect(x:24,y:top,width:688,height:148),xRadius:12,yRadius:12)
    rgb(0xE2E6EA).setStroke();outline.lineWidth=0.7;outline.stroke()
    label(names[index],44,top+14,14,primary,weight:.semibold)
    if index==0 {label("推荐",650,top+17,10,rgb(0x238571),weight:.medium)}
    rect(44,top+49,300,56,rgb(0x292B30),radius:7)
    scaled(44+(300-widths[index]*2)/2,top+55,2) {cpuMemoryNetwork(index,.white)}
    label("实际尺寸 · 约 \(Int(widths[index])) pt",392,top+29,9.5,secondary)
    rect(392,top+53,144,32,rgb(0x292B30),radius:5)
    scaled(392+(144-widths[index])/2,top+58,1) {cpuMemoryNetwork(index,.white)}
    rect(548,top+53,144,32,rgb(0xEBEDF0),radius:5)
    scaled(548+(144-widths[index])/2,top+58,1) {cpuMemoryNetwork(index,primary)}
    label(notes[index],44,top+121,10.5,secondary)
}
label("GPU 与温度不常驻；网速保持上下载、下上传的数字形式。G 为 GB，M 为 MB/s。",24,611,10.5,secondary)
NSGraphicsContext.restoreGraphicsState()
let output=destination.appendingPathComponent("menu-bar-memory-redesign.png")
try bitmap.representation(using:.png,properties:[:])!.write(to:output)
print(output.path)
