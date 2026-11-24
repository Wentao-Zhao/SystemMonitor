import SwiftUI
import MonitorCore

/// Restrained native surfaces; color is reserved for data and actionable state.
enum MonitorTheme {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor(srgbRed: dark ? 0.39 : 0.09, green: dark ? 0.83 : 0.48, blue: dark ? 0.61 : 0.33, alpha: 1)
    })
    static let surface = Color.primary.opacity(0.035)
    static let border = Color.primary.opacity(0.065)
    static func color(_ signal: MetricSignal) -> Color {
        switch signal {
        case .normal: return accent
        case .elevated: return .orange
        case .critical: return .red
        case .unknown: return .secondary
        }
    }
}

private struct PanelSurface: ViewModifier {
    let padding: CGFloat
    func body(content: Content) -> some View {
        content.padding(padding)
            .background(MonitorTheme.surface, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(MonitorTheme.border, lineWidth: 0.5))
    }
}
extension View {
    func panelSurface(padding: CGFloat = 14) -> some View { modifier(PanelSurface(padding: padding)) }
}

struct PanelIconButton: View {
    let symbol: String
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary).frame(width: 26, height: 26).contentShape(Rectangle())
        }.buttonStyle(.plain).help(title).accessibilityLabel(title)
    }
}

struct SegmentedMeter: View {
    let fraction: Double?
    let color: Color
    var segments = 24
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 3) {
                ForEach(0..<segments, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.primary.opacity(0.09))
                        .overlay(alignment: .leading) {
                            if let fraction {
                                let fill = min(1, max(0, fraction * Double(segments) - Double(index)))
                                RoundedRectangle(cornerRadius: 1).fill(color)
                                    .frame(width: max(0, (geometry.size.width - CGFloat(segments - 1) * 3) / CGFloat(segments)) * fill)
                            }
                        }
                }
            }
        }.accessibilityHidden(true)
    }
}

/// The same rounded-square dots as the menu bar, with a fixed time axis.
struct HistoryDotChart: View {
    let points: [HistoryPoint]
    let now: Double
    let window: Double
    let color: Color
    var ceiling: Double?
    var compact = false

    var body: some View {
        GeometryReader { geometry in
            let rows = compact ? 8 : 16
            let count = min(100, max(2, Int(geometry.size.width / (compact ? 5.0 : 5.8))))
            let maximum = max(ceiling ?? ((points.compactMap { point in
                point.value == nil ? nil : (point.maximum ?? point.value)
            }.max() ?? 1) * 1.12), 0.001)
            let columns = HistoryDotSeries.columns(points: points, now: now, window: window, fullScale: maximum, count: count)
            Canvas { context, size in
                let pitchX = size.width / CGFloat(count), pitchY = size.height / CGFloat(rows)
                let side = min(compact ? 2.8 : 3.6, pitchX - 1.3, pitchY - 1.3)
                guard side > 0 else { return }
                for column in columns.indices {
                    guard let reading = columns[column] else { continue }
                    for row in 0..<rows {
                        let x = CGFloat(column) * pitchX + (pitchX - side) / 2
                        let y = size.height - CGFloat(row + 1) * pitchY + (pitchY - side) / 2
                        let rect = CGRect(x: x, y: y, width: side, height: side)
                        let shape = Path(roundedRect: rect, cornerRadius: side * 0.2)
                        context.fill(shape, with: .color(.primary.opacity(compact ? 0.035 : 0.045)))
                        let fraction = min(1, max(0, reading.fraction * Double(rows) - Double(row)))
                        if fraction > 0 {
                            var fill = context
                            fill.clip(to: shape)
                            fill.fill(Path(CGRect(x: x, y: y + side * (1 - fraction), width: side, height: side * fraction)), with: .color(color))
                        }
                        let peakRow = min(rows - 1, max(0, Int(ceil(reading.peak * Double(rows))) - 1))
                        if row == peakRow && reading.peak - reading.fraction >= 1 / Double(rows) {
                            context.fill(shape, with: .color(color.opacity(0.32)))
                        }
                    }
                }
            }
            if columns.allSatisfy({ $0 == nil }) {
                Text("等待采样").font(.system(size: 10)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.accessibilityLabel("历史点阵，填充为平均值，淡点为峰值，缺失采样保留空白")
    }
}
