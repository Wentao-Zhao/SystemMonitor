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



// 15 columns, each the mean of two two-second samples: 60 seconds total.
let cpuBins:[CGFloat]=stride(from:0,to:cpu.count,by:2).map {(cpu[$0]+cpu[$0+1])/2}
func centerLabel(_ string:String,_ x:CGFloat,_ y:CGFloat,_ size:CGFloat,_ ink:NSColor) {
    let font=NSFont.systemFont(ofSize:size,weight:.medium)
    let w=(string as NSString).size(withAttributes:[.font:font]).width
    label(string,x-w/2,y,size,ink,weight:.medium)
}
func pressureColor(_ dark:Bool) -> NSColor {rgb(dark ? 0x63D39A : 0x18825C)}
func cpuTimeline(_ ink:NSColor) {
    label("CPU",1,0.2,6.8,ink.withAlphaComponent(0.76),weight:.medium)
    label("60s",25,0.6,6,ink.withAlphaComponent(0.48),weight:.medium,mono:true)
    for (i,value) in cpuBins.enumerated() {
        let h:CGFloat=12*value
        rect(1+CGFloat(i)*2.5,21.0-h,1.85,h,ink.withAlphaComponent(0.90),radius:0.35)
    }
}
func memoryGlyph(_ style:Int,_ ink:NSColor,_ accent:NSColor) {
    let fraction:CGFloat=0.62
    centerLabel("MEM",59,0.2,6.8,ink.withAlphaComponent(0.76))
    if style==0 {
        let outline=NSBezierPath(roundedRect:NSRect(x:52,y:10,width:14,height:11),xRadius:1.5,yRadius:1.5)
        ink.withAlphaComponent(0.14).setFill();outline.fill()
        NSGraphicsContext.saveGraphicsState();outline.addClip()
        rect(52,10+11*(1-fraction),14,11*fraction,accent)
        NSGraphicsContext.restoreGraphicsState()
    } else if style==1 {
        for i in 0..<8 {
            let x:CGFloat=48.2+CGFloat(i)*2.8
            let shape=NSBezierPath(roundedRect:NSRect(x:x,y:12.4,width:2,height:6.4),xRadius:0.5,yRadius:0.5)
            ink.withAlphaComponent(0.14).setFill();shape.fill()
            let part=min(1,max(0,fraction*8-CGFloat(i)))
            if part>0 {
                NSGraphicsContext.saveGraphicsState();shape.addClip()
                rect(x,12.4,2*part,6.4,accent)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    } else {
        for i in 0..<8 {
            let x:CGFloat=51.5+CGFloat(i%4)*4
            let y:CGFloat=i<4 ? 16.5 : 12.5
            let shape=NSBezierPath(roundedRect:NSRect(x:x,y:y,width:3,height:3),xRadius:0.6,yRadius:0.6)
            ink.withAlphaComponent(0.14).setFill();shape.fill()
            let part=min(1,max(0,fraction*8-CGFloat(i)))
            if part>0 {
                NSGraphicsContext.saveGraphicsState();shape.addClip()
                rect(x,y,3*part,3,accent)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }
}
func clearerStatus(_ style:Int,_ ink:NSColor,dark:Bool) {
    cpuTimeline(ink)
    memoryGlyph(style,ink,pressureColor(dark))
    arrow(80.5,3.3,down:true,ink.withAlphaComponent(0.62))
    arrow(80.5,14.1,down:false,ink.withAlphaComponent(0.62))
    rate("4.8","M",108.5,0.1,ink)
    rate("1.2","M",108.5,10.9,ink)
}
let width:CGFloat=736,height:CGFloat=672
let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(width*2),pixelsHigh:Int(height*2),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
let cg=NSGraphicsContext.current!.cgContext
cg.scaleBy(x:2,y:2);cg.translateBy(x:0,y:height);cg.scaleBy(x:1,y:-1)
let primary=rgb(0x242A31),secondary=rgb(0x787F88)
rect(0,0,width,height,rgb(0xF4F5F7))
label("CPU 看历史，内存看填充",24,20,23,primary,weight:.semibold)
label("CPU 标明 60 秒窗口；内存用彩色填充表达占用，不常驻百分比数字。",24,60,11.5,secondary)
let titles=["A   液位色块","B   分段容量槽","C   点阵填充"]
let captions=["填充高度表示内存使用率，小方块即可看出还有多少余量。","已亮格数表示占用，更容易粗略判断比例。","用点阵的亮起面积表达占用，轮廓更轻。"]
for index in 0..<3 {
    let top:CGFloat=102+CGFloat(index)*166
    rect(24,top,688,150,.white,radius:12)
    let outline=NSBezierPath(roundedRect:NSRect(x:24,y:top,width:688,height:150),xRadius:12,yRadius:12)
    rgb(0xE2E6EA).setStroke();outline.lineWidth=0.7;outline.stroke()
    label(titles[index],44,top+14,14,primary,weight:.semibold)
    if index==1 {label("推荐",650,top+17,10,rgb(0x238571),weight:.medium)}
    rect(44,top+50,300,57,rgb(0x292B30),radius:7)
    scaled(70.8,top+54.3,2.2) {clearerStatus(index,.white,dark:true)}
    label("接近实际尺寸 · 约 112 pt",392,top+30,9.5,secondary)
    rect(392,top+54,144,32,rgb(0x292B30),radius:5)
    scaled(408,top+59,1) {clearerStatus(index,.white,dark:true)}
    rect(548,top+54,144,32,rgb(0xEBEDF0),radius:5)
    scaled(564,top+59,1) {clearerStatus(index,primary,dark:false)}
    label(captions[index],44,top+122,10.5,secondary)
}
label("CPU 每根柱 = 4 秒平均负载，15 根覆盖 1 分钟；左侧是过去，右侧是现在。",24,616,10.5,primary)
label("内存填充表示已用比例，颜色提示系统内存压力；精确数据悬停查看。",24,642,10.5,secondary)
NSGraphicsContext.restoreGraphicsState()
let output=destination.appendingPathComponent("menu-bar-memory-non-ring.png")
try bitmap.representation(using:.png,properties:[:])!.write(to:output)
print(output.path)
