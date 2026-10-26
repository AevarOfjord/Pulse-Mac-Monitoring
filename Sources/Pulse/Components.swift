import SwiftUI
import AppKit
import Charts
import MonitorCore

// Name the property-wrapper type explicitly: newer SDKs also expose a State
// macro whose plugin isn't bundled with the standalone Command Line Tools.
typealias ViewState<Value> = SwiftUI.State<Value>

enum Palette {
    static let background = adaptive(light: 0xF4F6F8, dark: 0x0D1117)
    static let sidebar = adaptive(light: 0xECEFF3, dark: 0x10161E)
    static let panel = adaptive(light: 0xFFFFFF, dark: 0x141B24)
    static let border = adaptive(light: 0xD4DCE5, dark: 0x26313E)
    static let muted = adaptive(light: 0x536174, dark: 0x8290A4)
    static let mint = adaptive(light: 0x006B50, dark: 0x74E2BE)
    static let blue = adaptive(light: 0x245CCD, dark: 0x79A9FF)
    static let purple = adaptive(light: 0x6E4ABD, dark: 0xB49AFF)
    static let amber = adaptive(light: 0x915410, dark: 0xE9B978)
    static let cyan = adaptive(light: 0x00697B, dark: 0x6BD2E3)

    // Resolve against the drawing view's appearance, rather than caching the
    // system appearance at launch. Windows and menu extras update live.
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                           green: Double((value >> 8) & 255) / 255,
                           blue: Double(value & 255) / 255, alpha: 1)
        })
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

struct Panel<Content: View>: View {
    var title: String
    var subtitle: String? = nil
    var symbol: String? = nil
    var color: Color = Palette.mint
    var inspection: ChartInspection? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                HStack(spacing: 9) {
                    if let symbol { Image(systemName: symbol).foregroundStyle(color).font(.system(size: 14)) }
                    Text(title).font(.system(size: 14, weight: .semibold))
                }.fixedSize()
                if let inspection { ChartInspectionView(inspection: inspection) }
                else { Spacer() }
                if let subtitle { Text(subtitle).font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.muted).fixedSize() }
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.border.opacity(0.7), lineWidth: 1))
    }
}

struct MetricCard: View {
    let title: String
    let icon: String
    let value: String
    var unit: String = "%"
    let caption: String
    let color: Color
    let values: [Double]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Image(systemName: icon).foregroundStyle(color); Text(title).foregroundStyle(Palette.muted); Spacer() }.font(.system(size: 12, weight: .medium))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(unit).font(.system(size: 15)).foregroundStyle(Palette.muted)
                Spacer(minLength: 0)
                Sparkline(values: values, color: color).frame(width: 75, height: 30).accessibilityHidden(true)
            }
            Text(caption).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.border.opacity(0.7)))
    }
}

struct Sparkline: View {
    var values: [Double]
    var color: Color
    var body: some View {
        GeometryReader { geometry in
            let maxValue = max(10, values.max() ?? 100)
            Path { path in
                guard values.count > 1 else { return }
                for (i, value) in values.enumerated() {
                    let point = CGPoint(x: geometry.size.width * Double(i) / Double(values.count - 1),
                                        y: geometry.size.height * (1 - value / maxValue))
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }.stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
    }
}

enum ChartUnit {
    case percent, rate, celsius
    func label(_ value: Double) -> String {
        switch self {
        case .percent: return "\(Int(value))%"
        case .rate: return Format.rate(value)
        case .celsius: return "\(Int(value)) °C"
        }
    }
}

struct TimeChart: View {
    let history: [HistoryPoint]
    let color: Color
    var secondaryColor: Color = Palette.blue
    var maximum: Double? = 100
    var unit: ChartUnit = .percent
    var seconds: Double = 120
    var value: (SystemSnapshot) -> Double?
    var secondary: ((SystemSnapshot) -> Double?)? = nil
    @Binding var selection: Date?
    private var end: Date { history.last?.date ?? Date() }
    private var visibleSamples: [HistoryPoint] { history.filter { $0.date >= end.addingTimeInterval(-seconds) } }
    private var points: [HistoryPoint] { HistoryBuffer.chartSamples(visibleSamples) }
    private var entries: [(point: HistoryPoint, primary: String, secondary: String)] {
        var primary = 0; var second = 0
        return points.map { point in
            if value(point.snapshot) == nil { primary += 1 }
            if secondary?(point.snapshot) == nil { second += 1 }
            return (point, "\(point.segment)-\(primary)", "\(point.segment)-\(second)")
        }
    }
    private var ceiling: Double {
        maximum ?? max(unit == .rate ? 1024 : 1, (points.flatMap { [value($0.snapshot) ?? 0, secondary?($0.snapshot) ?? 0] }.max() ?? 1) * 1.2)
    }
    private var floor: Double {
        unit == .celsius ? min(0, (points.compactMap { value($0.snapshot) }.min() ?? 0) - 5) : 0
    }
    var body: some View {
        Chart {
            ForEach(entries, id: \.point.id) { entry in
                let point = entry.point
                if let number = value(point.snapshot) {
                    AreaMark(x: .value("Time", point.date), y: .value("Value", number), series: .value("Segment", entry.primary))
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.19), color.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.linear)
                    LineMark(x: .value("Time", point.date), y: .value("Value", number), series: .value("Metric", "Primary-\(entry.primary)"))
                        .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2)).interpolationMethod(.linear)
                }
                if let number = secondary?(point.snapshot) {
                    LineMark(x: .value("Time", point.date), y: .value("Value", number), series: .value("Metric", "Secondary-\(entry.secondary)"))
                        .foregroundStyle(secondaryColor).lineStyle(StrokeStyle(lineWidth: 1.7)).interpolationMethod(.linear)
                }
            }
            if let nearest = selectedChartSample(in: history, at: selection, seconds: seconds) {
                RuleMark(x: .value("Selected", nearest.date)).foregroundStyle(Palette.muted.opacity(0.6))
            }
        }
        .chartXScale(domain: end.addingTimeInterval(-seconds)...end)
        .chartYScale(domain: floor...ceiling)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { axis in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4])).foregroundStyle(Palette.border)
                AxisValueLabel {
                    if let number = axis.as(Double.self) {
                        Text(unit.label(number)).font(.system(size: 9)).foregroundStyle(Palette.muted)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { axis in
                AxisValueLabel(format: .dateTime.hour().minute().second()).font(.system(size: 9)).foregroundStyle(Palette.muted)
            }
        }
        .chartXSelection(value: $selection)
        // macOS defaults to hover selection. Explicitly support clicking and
        // dragging, retaining the reading after the pointer is released.
        .chartGesture { proxy in
            DragGesture(minimumDistance: 0)
                .onChanged { proxy.selectXValue(at: $0.location.x) }
        }
        .chartLegend(.hidden)
        .accessibilityLabel("Live activity chart")
        .help("Click or drag across the chart to inspect a reading.")
    }
}

struct DotLabel: View {
    let text: String
    let color: Color
    var body: some View { HStack(spacing: 6) { Circle().fill(color).frame(width: 5, height: 5); Text(text).font(.system(size: 10)).foregroundStyle(Palette.muted) } }
}

struct StatRow: View {
    let label: String
    let value: String
    var color: Color = .primary
    var body: some View {
        HStack { Text(label).foregroundStyle(Palette.muted); Spacer(); Text(value).foregroundStyle(color).monospacedDigit() }.font(.system(size: 12))
    }
}

struct UsageBar: View {
    var fraction: Double
    var color: Color
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.border)
                Capsule().fill(color).frame(width: geometry.size.width * min(1, max(0, fraction)))
            }
        }.frame(height: 6)
    }
}
