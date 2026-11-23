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

struct Sparkline: View {
    let points: [HistoryPoint]
    let now: Double
    let window: Double
    let color: Color
    var ceiling: Double?
    var compact = false
    var bars = false

    var body: some View {
        GeometryReader { geometry in
            let maximum = max(ceiling ?? ((points.compactMap { $0.value == nil ? nil : ($0.maximum ?? $0.value) }.max() ?? 1) * 1.12), 0.001)
            let segments = plotSegments(points)
            ZStack {
                if !compact {
                    Path { path in
                        for fraction in [0.0, 0.5, 1.0] {
                            let y = geometry.size.height * fraction
                            path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                        }
                    }.stroke(Color.primary.opacity(0.065), style: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                }
                Path { path in
                    for point in segments.flatMap({ $0 }) {
                        guard point.value != nil, let low = point.minimum, let high = point.maximum, high > low else { continue }
                        path.move(to: position(point, low, in: geometry.size, maximum: maximum))
                        path.addLine(to: position(point, high, in: geometry.size, maximum: maximum))
                    }
                }.stroke(color.opacity(0.22), lineWidth: 1)
                if bars {
                    Path { path in
                        for point in segments.flatMap({ $0 }) {
                            guard let value = point.value, value.isFinite else { continue }
                            let p = position(point, value, in: geometry.size, maximum: maximum)
                            path.move(to: CGPoint(x: p.x, y: geometry.size.height)); path.addLine(to: p)
                        }
                    }.stroke(color.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                } else {
                    Path { path in
                        for segment in segments {
                            guard let first = segment.first, let value = first.value else { continue }
                            let start = position(first, value, in: geometry.size, maximum: maximum)
                            path.move(to: CGPoint(x: start.x, y: geometry.size.height)); path.addLine(to: start)
                            for point in segment.dropFirst() {
                                if let value = point.value { path.addLine(to: position(point, value, in: geometry.size, maximum: maximum)) }
                            }
                            if let last = segment.last, let value = last.value {
                                path.addLine(to: CGPoint(x: position(last, value, in: geometry.size, maximum: maximum).x, y: geometry.size.height))
                            }
                            path.closeSubpath()
                        }
                    }.fill(color.opacity(0.09))
                    Path { path in
                        for segment in segments {
                            for (index, point) in segment.enumerated() {
                                guard let value = point.value else { continue }
                                let p = position(point, value, in: geometry.size, maximum: maximum)
                                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
                            }
                        }
                    }.stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
                if points.compactMap(\.value).isEmpty {
                    Text("等待采样").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
        }.accessibilityLabel("近期趋势，缺失采样保留空白")
    }
    private func position(_ point: HistoryPoint, _ value: Double, in size: CGSize, maximum: Double) -> CGPoint {
        CGPoint(x: size.width * min(1, max(0, (point.time - now + window) / window)),
                y: size.height * (1 - min(1, max(0, value / maximum))))
    }
}
