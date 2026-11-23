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

// A: all fields share the same two row centres, no enclosing chrome.
func dualTrack(_ ink:NSColor) {
    for (i,values) in [cpu,gpu].enumerated() {
        let y:CGFloat=CGFloat(i)*10.8
        label(i==0 ? "CPU" : "GPU",0,y+1.0,6.9,ink.withAlphaComponent(0.64),weight:.medium)
        stroke([(16,y+9),(48,y+9)],ink.withAlphaComponent(0.13),width:0.35)
        history(values,16,y+2.2,32,6.8,ink.withAlphaComponent(0.92))
    }
    memory(57,20,ink)
    arrow(88,3.3,down:true,ink.withAlphaComponent(0.62))
    arrow(88,14.1,down:false,ink.withAlphaComponent(0.62))
    rate("4.8","M",114,0.1,ink)
    rate("1.2","M",114,10.9,ink)
}

// B: identical-height instrument cells, labels and values use one type system.
func instrumentCells(_ ink:NSColor) {
    for (index,origin) in [CGFloat(2),38].enumerated() {
        rect(origin,0,32,22,ink.withAlphaComponent(0.065),radius:3)
        label(index==0 ? "CPU" : "GPU",origin+4,0.5,6.6,ink.withAlphaComponent(0.65),weight:.medium)
        history(index==0 ? cpu : gpu,origin+4,10.5,24,8.2,ink.withAlphaComponent(0.92))
    }
    rect(74,0,26,22,ink.withAlphaComponent(0.065),radius:3)
    label("MEM",78,0.5,6.6,ink.withAlphaComponent(0.65),weight:.medium)
    textRight("62%",96,9.7,8.3,ink)
    rect(104,0,40,22,ink.withAlphaComponent(0.065),radius:3)
    arrow(109,3.3,down:true,ink.withAlphaComponent(0.62))
    arrow(109,14.1,down:false,ink.withAlphaComponent(0.62))
    rate("4.8","M",140,0.1,ink,size:8.3)
    rate("1.2","M",140,10.9,ink,size:8.3)
}

// C: a shared plot with two line styles; memory and traffic retain clear values.
func signalWindow(_ ink:NSColor) {
    stroke([(1,20),(37,20)],ink.withAlphaComponent(0.13),width:0.35)
    history(gpu,1,2,36,18,ink.withAlphaComponent(0.58),dashed:true)
    history(cpu,1,2,36,18,ink.withAlphaComponent(0.95))
    memory(46,19,ink)
    arrow(76,3.3,down:true,ink.withAlphaComponent(0.62))
    arrow(76,14.1,down:false,ink.withAlphaComponent(0.62))
    rate("4.8","M",102,0.1,ink)
    rate("1.2","M",102,10.9,ink)
}
func widget(_ index:Int,_ ink:NSColor) {
    if index==0 {dualTrack(ink)} else if index==1 {instrumentCells(ink)} else {signalWindow(ink)}
}
let widths:[CGFloat]=[118,146,106]
let names=["A   双行轨道","B   四格仪表","C   轻量信号窗"]
let subtitles=["上下对齐的两条历史曲线，内存与网速保持同一行距。","CPU、GPU、内存、网络各成一格，边界和层级更明确。","合并 CPU/GPU 图窗，用虚实线区分，整体更克制。"]
let notes=["上 CPU / 下 GPU · 内存百分比 + 横向容量条 · 上下载 / 下上传", "模块标签与数据各占一层；四格等高，更清楚，也更宽一些。", "CPU 实线 / GPU 虚线 · 两条曲线可能交叠，悬停查看精确读数。"]

let width:CGFloat=736,height:CGFloat=780
let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(width*2),pixelsHigh:Int(height*2),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
let cg=NSGraphicsContext.current!.cgContext
cg.scaleBy(x:2,y:2);cg.translateBy(x:0,y:height);cg.scaleBy(x:1,y:-1)
let primary=rgb(0x242A31),secondary=rgb(0x787F88)
rect(0,0,width,height,rgb(0xF4F5F7))
label("菜单栏 · 三个新方案",24,20,23,primary,weight:.semibold)
label("同一组示例数据 · CPU/GPU 最近 60 秒 · 固定 0–100% 刻度",24,60,11.5,secondary)
for index in 0..<3 {
    let top:CGFloat=102+CGFloat(index)*206
    rect(24,top,688,188,.white,radius:12)
    let outline=NSBezierPath(roundedRect:NSRect(x:24,y:top,width:688,height:188),xRadius:12,yRadius:12)
    rgb(0xE2E6EA).setStroke();outline.lineWidth=0.7;outline.stroke()
    label(names[index],44,top+15,14,primary,weight:.semibold)
    label(subtitles[index],44,top+40,11,secondary)
    if index==0 {label("推荐",650,top+17,10,rgb(0x238571),weight:.medium)}
    rect(44,top+73,324,60,rgb(0x292B30),radius:7)
    scaled(44+(324-widths[index]*2)/2,top+81,2) {widget(index,.white)}
    label("2× 放大",44,top+58,9,secondary)
    label("实际尺寸 · 约 \(Int(widths[index])) pt",448,top+51,9.5,secondary)
    rect(448,top+71,240,30,rgb(0x292B30),radius:5)
    scaled(448+(240-widths[index])/2,top+75,1) {widget(index,.white)}
    rect(448,top+111,240,30,rgb(0xEBEDF0),radius:5)
    scaled(448+(240-widths[index])/2,top+115,1) {widget(index,primary)}
    label(notes[index],44,top+158,10.2,secondary)
}
label("温度暂不常驻。网速始终为双行数字，不使用网速趋势线；M 表示 MB/s。",24,747,10.5,secondary)
NSGraphicsContext.restoreGraphicsState()
let output=destination.appendingPathComponent("menu-bar-redesign-three.png")
try bitmap.representation(using:.png,properties:[:])!.write(to:output)
print(output.path)
