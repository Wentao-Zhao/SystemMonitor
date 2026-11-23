import AppKit
import MonitorCore

struct DotMatrixFrame {
    let id: String
    let presentation: MetricPresentation
    let fraction: Double?
    let bins: [Double?]
    let signal: MetricSignal
}

/// The same drawing code supplies the status items, settings preview and visual checks.
enum MenuBarRenderer {
    static let cell: CGFloat = 2.2
    static let pitch: CGFloat = 2.8
    static let historyWidth: CGFloat = 14 * pitch + cell

    static func frames(for selections: [MenuMetricSelection], snapshot: MonitorSnapshot, history: MetricHistory,
                       now: Double, refreshInterval: Double, previous: [String: MetricSignal] = [:]) -> [DotMatrixFrame] {
        selections.map { selection in
            let metric = selection.metric
            let fraction = metric.fraction(in: snapshot, override: selection.scale)
            let scale = metric.fullScale(in: snapshot, override: selection.scale) ?? 0
            let bins = DotMatrixSeries.bins(points: history.points(for: metric.id, since: now - 68), now: now,
                                           fullScale: scale, maxHold: max(3, refreshInterval * 1.6))
            let recent = bins.suffix(3).compactMap { $0 }
            let colorFraction: Double? = fraction == nil ? nil : selection.presentation == .history && !recent.isEmpty ? recent.reduce(0, +) / Double(recent.count) : fraction
            let signal = metric.signal(in: snapshot, fraction: colorFraction, previous: previous[selection.id] ?? .unknown)
            return DotMatrixFrame(id: metric.id, presentation: selection.presentation, fraction: fraction, bins: bins, signal: signal)
        }
    }

    static func image(frames: [DotMatrixFrame], dark: Bool, paused: Bool = false) -> NSImage {
        var starts: [CGFloat] = []
        var x: CGFloat = 4
        for (index, frame) in frames.enumerated() {
            if index > 0 { x += frames[index - 1].presentation == .history || frame.presentation == .history ? 10 : 6 }
            starts.append(x)
            x += frame.presentation == .history ? historyWidth : cell
        }
        let width: CGFloat = frames.isEmpty ? 17 : max(10, x + 4)
        let image = NSImage(size: NSSize(width: width, height: 22), flipped: false) { _ in
            let ink = dark ? NSColor.white : rgb(0x242A31)
            if frames.isEmpty {
                // A neutral launcher preserves access after every data indicator is removed.
                for row in 0..<3 { for column in 0..<3 {
                    fill(NSRect(x: 3.4 + CGFloat(column) * 4, y: 5.9 + CGFloat(row) * 4, width: 2.2, height: 2.2), ink.withAlphaComponent(0.65))
                } }
            }
            for (index, frame) in frames.enumerated() {
                let color = paused ? ink.withAlphaComponent(0.3) : color(frame.signal, dark: dark)
                if frame.presentation == .instant {
                    column(at: starts[index], fraction: frame.fraction, color: color, ink: ink, ghost: 0.14)
                } else {
                    for (bin, value) in frame.bins.enumerated() {
                        column(at: starts[index] + CGFloat(bin) * pitch, fraction: value, color: color, ink: ink, ghost: 0.035, markUnavailable: false)
                    }
                    if frame.fraction == nil { unavailable(at: starts[index] + historyWidth / 2 - 1.1, ink: ink) }
                }
            }
            return true
        }
        // State colors are intentional; template images would discard them.
        image.isTemplate = false
        image.accessibilityDescription = frames.isEmpty ? "SystemMonitor" : "SystemMonitor 指标点阵"
        return image
    }

    private static func column(at x: CGFloat, fraction: Double?, color: NSColor, ink: NSColor, ghost: CGFloat, markUnavailable: Bool = true) {
        for row in 0..<6 {
            let rect = NSRect(x: x, y: 2.9 + CGFloat(row) * pitch, width: cell, height: cell)
            fill(rect, ink.withAlphaComponent(ghost))
            guard let fraction else { continue }
            let part = CGFloat(min(1, max(0, fraction * 6 - Double(row))))
            if part > 0 {
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: rect, xRadius: 0.55, yRadius: 0.55).addClip()
                color.setFill(); NSRect(x: rect.minX, y: rect.minY, width: cell, height: cell * part).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        if fraction == nil && markUnavailable { unavailable(at: x, ink: ink) }
    }

    private static func unavailable(at x: CGFloat, ink: NSColor) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x - 0.5, y: 9)); path.line(to: NSPoint(x: x + 2.7, y: 13))
        path.lineWidth = 0.8; path.lineCapStyle = .round
        ink.withAlphaComponent(0.55).setStroke(); path.stroke()
    }
    private static func fill(_ rect: NSRect, _ color: NSColor) {
        color.setFill(); NSBezierPath(roundedRect: rect, xRadius: 0.55, yRadius: 0.55).fill()
    }
    private static func rgb(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    private static func color(_ state: MetricSignal, dark: Bool) -> NSColor {
        switch state {
        case .normal: return rgb(dark ? 0x63D39A : 0x18825C)
        case .elevated: return rgb(dark ? 0xF4C35C : 0xAA6A10)
        case .critical: return rgb(dark ? 0xF38080 : 0xB53647)
        case .unknown: return (dark ? NSColor.white : rgb(0x242A31)).withAlphaComponent(0.6)
        }
    }
}
