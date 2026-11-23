import AppKit
import MonitorCore

@main
enum RenderMenuPreview {
    static func main() throws {
        _ = NSApplication.shared
        let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "design/menu-bar-layouts/menu-bar-implemented.png")
        let width: CGFloat = 736, height: CGFloat = 390
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: Int(height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let cg = NSGraphicsContext.current!.cgContext
        cg.scaleBy(x: 2, y: 2)
        cg.translateBy(x: 0, y: height); cg.scaleBy(x: 1, y: -1)
        func fill(_ rect: NSRect, _ color: NSColor, radius: CGFloat = 0) {
            color.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        }
        func text(_ string: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, bold: Bool = false) {
            NSGraphicsContext.saveGraphicsState()
            cg.translateBy(x: x, y: y); cg.scaleBy(x: 1, y: -1)
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular), .foregroundColor: NSColor(calibratedWhite: 0.28, alpha: 1)]
            let h = (string as NSString).size(withAttributes: attributes).height
            (string as NSString).draw(at: NSPoint(x: 0, y: -h), withAttributes: attributes)
            NSGraphicsContext.restoreGraphicsState()
        }
        let values: [Double?] = [0.2, 0.2, 0.3, 0.5, 0.7, 0.75, 0.6, 0.4, 0.3, 0.4, 0.5, 0.4, 0.3, 0.25, 0.2]
        let cpu = DotMatrixFrame(id: "cpu.total", presentation: .history, fraction: 0.2, bins: values, signal: .normal)
        func instant(_ id: String, _ fraction: Double?, _ signal: MetricSignal) -> DotMatrixFrame {
            DotMatrixFrame(id: id, presentation: .instant, fraction: fraction, bins: [], signal: signal)
        }
        let samples: [(String, [DotMatrixFrame])] = [
            ("默认 · CPU 历史 + 内存 / 下载 / 上传实时点列", [cpu, instant("memory.percent", 0.62, .normal), instant("network.in", 0.48, .normal), instant("network.out", 0.12, .normal)]),
            ("按需扩展 · 每个具体读数可单独添加、移除", [cpu, instant("memory.percent", 0.62, .normal), instant("disk.percent", 0.88, .critical), instant("cpu.temperature", 0.76, .elevated), instant("fan.0", 0.31, .normal), instant("network.in", 0.48, .normal), instant("network.out", 0.12, .normal)]),
            ("不可用 / 压力未知 · 斜杠与灰色区分正常低负载", [cpu, instant("memory.percent", 0.62, .unknown), instant("network.in", nil, .unknown)]),
            ("全部移除 · 保留应用入口", [])
        ]
        fill(NSRect(x: 0, y: 0, width: width, height: height), NSColor(calibratedWhite: 0.96, alpha: 1))
        text("B · 已接入的原生点阵渲染", 24, 18, 22, bold: true)
        text("图形来自应用实际渲染器 · 以下读数为外观验收样例", 24, 53, 11)
        for (index, sample) in samples.enumerated() {
            let y: CGFloat = 85 + CGFloat(index) * 73
            text(sample.0, 24, y, 11)
            for (column, dark) in [true, false].enumerated() {
                let x: CGFloat = 24 + CGFloat(column) * 352
                fill(NSRect(x: x, y: y + 23, width: 336, height: 36), dark ? NSColor(calibratedWhite: 0.16, alpha: 1) : NSColor(calibratedWhite: 0.91, alpha: 1), radius: 5)
                let image = MenuBarRenderer.image(frames: sample.1, dark: dark)
                NSGraphicsContext.saveGraphicsState()
                cg.translateBy(x: x + 18, y: y + 52); cg.scaleBy(x: 1, y: -1)
                image.draw(in: NSRect(x: 0, y: 0, width: image.size.width, height: 22), from: .zero, operation: .sourceOver, fraction: 1)
                NSGraphicsContext.restoreGraphicsState()
                precondition(!image.isTemplate, "semantic colors must not become template ink")
                precondition(image.size.height == 22 && image.size.width > 0, "valid status image geometry")
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
        print(destination.path)
    }
}
