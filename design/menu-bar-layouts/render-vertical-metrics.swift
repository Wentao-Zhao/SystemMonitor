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

// One appearance-aware semantic palette for history and selectable metric columns.
func stateColor(_ level:Int,_ dark:Bool)->NSColor {
    let darkColors:[UInt32]=[0x63D39A,0xF4C35C,0xF38080]
    let lightColors:[UInt32]=[0x18825C,0xAA6A10,0xB53647]
    return rgb((dark ? darkColors : lightColors)[max(0,min(2,level))])
}
func dotColumn(_ x:CGFloat,_ fraction:CGFloat,_ color:NSColor,_ ink:NSColor,ghost:CGFloat=0.14) {
    let cell:CGFloat=2.2,pitch:CGFloat=2.8,top:CGFloat=2.9
    for index in 0..<6 {
        let y=top+CGFloat(5-index)*pitch
        let shape=NSBezierPath(roundedRect:NSRect(x:x,y:y,width:cell,height:cell),xRadius:0.55,yRadius:0.55)
        ink.withAlphaComponent(ghost).setFill();shape.fill()
        let part=min(1,max(0,fraction*6-CGFloat(index)))
        if part>0 {
            NSGraphicsContext.saveGraphicsState();shape.addClip()
            rect(x,y+cell*(1-part),cell,cell*part,color)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
func smoothCurve(_ values:[CGFloat],_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat)->NSBezierPath {
    let points=values.enumerated().map {NSPoint(x:x+CGFloat($0.offset)*w/CGFloat(values.count-1),y:y+h*(1-$0.element))}
    let path=NSBezierPath();path.move(to:points[0])
    for i in 0..<(points.count-1) {
        let a=points[max(0,i-1)],b=points[i],c=points[i+1],d=points[min(points.count-1,i+2)]
        path.curve(to:c,controlPoint1:NSPoint(x:b.x+(c.x-a.x)/6,y:b.y+(c.y-a.y)/6),controlPoint2:NSPoint(x:c.x-(d.x-b.x)/6,y:c.y-(d.y-b.y)/6))
    }
    return path
}
let sampleFractions:[CGFloat]=[0.62,0.88,0.31,0.47,0.95,0.22]
let sampleStates=[0,1,0,0,2,0]
func widget(_ variant:Int,_ ink:NSColor,dark:Bool,count:Int=2,cpuState:Int=0) {
    let color=stateColor(cpuState,dark)
    if variant==0 {
        for (i,value) in cpuBins.enumerated() {dotColumn(1+CGFloat(i)*2.8,value,color,ink,ghost:0.045)}
    } else {
        let curve=smoothCurve(cpu,1,2.9,41.4,16.2)
        let area=curve.copy() as! NSBezierPath
        area.line(to:NSPoint(x:42.4,y:19.1));area.line(to:NSPoint(x:1,y:19.1));area.close()
        color.withAlphaComponent(dark ? 0.15 : 0.11).setFill();area.fill()
        color.setStroke();curve.lineWidth=0.95;curve.lineCapStyle = .round;curve.lineJoinStyle = .round;curve.stroke()
    }
    for i in 0..<count {dotColumn(52+CGFloat(i)*6,sampleFractions[i],stateColor(sampleStates[i],dark),ink)}
    let netX:CGFloat=72+CGFloat(count-2)*6
    arrow(netX,3.3,down:true,ink.withAlphaComponent(0.62))
    arrow(netX,14.1,down:false,ink.withAlphaComponent(0.62))
    rate("4.8","M",netX+28,0.1,ink)
    rate("1.2","M",netX+28,10.9,ink)
}
let width:CGFloat=736,height:CGFloat=676
let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(width*2),pixelsHigh:Int(height*2),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
let cg=NSGraphicsContext.current!.cgContext
cg.scaleBy(x:2,y:2);cg.translateBy(x:0,y:height);cg.scaleBy(x:1,y:-1)
let primary=rgb(0x242A31),secondary=rgb(0x787F88)
rect(0,0,width,height,rgb(0xF4F5F7))
label("一列一个指标",24,20,23,primary,weight:.semibold)
label("向上填充表达占比 · 整列颜色表达状态 · CPU 保留最近一分钟的历史",24,59,11.5,secondary)
func card(_ variant:Int,_ y:CGFloat,_ title:String,_ subtitle:String) {
    rect(24,y,688,181,.white,radius:12)
    let outline=NSBezierPath(roundedRect:NSRect(x:24,y:y,width:688,height:181),xRadius:12,yRadius:12)
    rgb(0xE2E6EA).setStroke();outline.lineWidth=0.7;outline.stroke()
    label(title,44,y+15,15,primary,weight:.semibold)
    label("放大",44,y+44,9.5,secondary)
    label("实际尺寸 · 深 / 浅",374,y+44,9.5,secondary)
    rect(44,y+65,286,67,rgb(0x292B30),radius:7)
    scaled(60,y+72,2.4) {widget(variant,.white,dark:true)}
    rect(374,y+77,150,32,rgb(0x292B30),radius:5)
    scaled(397,y+82,1) {widget(variant,.white,dark:true)}
    rect(538,y+77,150,32,rgb(0xEBEDF0),radius:5)
    scaled(561,y+82,1) {widget(variant,primary,dark:false)}
    label(subtitle,44,y+150,11,secondary)
}
card(1,98,"A · 曲线 + 竖向点列","CPU 用同色细线和淡填充，整段随近期平均负载变色；右侧为两列自选指标。")
card(0,295,"B · 历史也点阵化","CPU 每列代表一段时间，右侧每列代表一个指标；颜色仍按整块状态变化。")
label("按需加列",24,503,13,primary,weight:.semibold)
let xs:[CGFloat]=[24,258,492]
for (i,count) in [2,4,6].enumerated() {
    let x=xs[i]
    label("\(count) 个自选指标",x,529,10.5,secondary)
    rect(x,551,220,41,rgb(0x292B30),radius:6)
    let w:CGFloat=104+CGFloat(count-2)*6
    scaled(x+(220-w)/2,560.5,1) {widget(1,.white,dark:true,count:count)}
}
let legendY:CGFloat=618
for (i,item) in [("正常",0),("偏高",1),("紧张",2)].enumerated() {
    let x:CGFloat=24+CGFloat(i)*77
    rect(x,legendY+3,6,6,stateColor(item.1,false),radius:1.5)
    label(item.0,x+12,legendY,10.5,secondary)
}
label("颜色语义统一；每项按自身的负载 / 压力判断。",286,legendY,10.5,secondary)
label("设计示例 · 图标内不放名称与百分比，精确信息移入悬停详情。",24,649,10.5,secondary)
NSGraphicsContext.restoreGraphicsState()
let output=destination.appendingPathComponent("menu-bar-vertical-metrics.png")
try bitmap.representation(using:.png,properties:[:])!.write(to:output)
print(output.path)
