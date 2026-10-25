import SwiftUI
import MonitorCore

func selectedChartSample(in history: [HistoryPoint], at date: Date?, seconds: Double) -> HistoryPoint? {
    guard let date, let end = history.last?.date,
          date >= end.addingTimeInterval(-seconds), date <= end else { return nil }
    return history.filter { $0.date >= end.addingTimeInterval(-seconds) }
        .min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
}

struct ChartInspection {
    struct Reading: Identifiable {
        let label: String
        let value: String
        let color: Color
        var id: String { label }
    }
    var date: Date?
    var readings: [Reading] = []
}

enum ChartMetric {
    case cpu, gpu, memory, storage, network, download
    case temperature(TemperatureGroup)

    var color: Color {
        switch self {
        case .cpu: return Palette.mint
        case .gpu: return Palette.purple
        case .memory: return Palette.blue
        case .storage: return Palette.amber
        case .temperature: return Palette.amber
        case .network, .download: return Palette.cyan
        }
    }

    func inspection(in history: [HistoryPoint], at date: Date?, seconds: Double) -> ChartInspection {
        guard let point = selectedChartSample(in: history, at: date, seconds: seconds) else { return ChartInspection() }
        let sample = point.snapshot
        func reading(_ label: String, _ value: Double?, _ color: Color, rate: Bool = false) -> ChartInspection.Reading {
            ChartInspection.Reading(label: label,
                                    value: value.map { rate ? Format.rate($0) : "\(Format.percent($0))%" } ?? "Unavailable",
                                    color: color)
        }
        let readings: [ChartInspection.Reading]
        switch self {
        case .cpu:
            readings = [reading("Total", sample.cpu, .primary),
                        reading("User", sample.cpu == nil ? nil : sample.cpuUser, Palette.mint),
                        reading("System", sample.cpu == nil ? nil : sample.cpuSystem, Palette.blue)]
        case .gpu:
            readings = [reading("Device", sample.gpu.utilization, color)]
        case .memory:
            readings = [reading("Used", sample.memory?.percent, color)]
        case .storage:
            readings = [reading("Read", sample.disk.activity?.incoming, color, rate: true),
                        reading("Write", sample.disk.activity?.outgoing, Palette.blue, rate: true)]
        case .network:
            readings = [reading("Download", sample.network?.incoming, color, rate: true),
                        reading("Upload", sample.network?.outgoing, Palette.blue, rate: true)]
        case .download:
            readings = [reading("Download", sample.network?.incoming, color, rate: true)]
        case .temperature(let group):
            readings = [.init(label: group.title + " max", value: sample.temperatures?.maximum(for: group).map { Format.temperature($0) } ?? "Unavailable", color: color)]
        }
        if case .temperature = self { return ChartInspection(date: sample.temperatures?.sampledAt ?? point.date, readings: readings) }
        return ChartInspection(date: point.date, readings: readings)
    }
}

struct ChartInspectionView: View {
    let inspection: ChartInspection
    private var timestamp: some View {
        Text("Selected · \(inspection.date!.formatted(date: .omitted, time: .standard))")
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.7)
    }
    var body: some View {
        Group {
            if inspection.date != nil {
                ViewThatFits(in: .horizontal) {
                    VStack(spacing: 4) {
                        timestamp
                        HStack(spacing: 12) {
                            ForEach(inspection.readings) { reading in
                                HStack(spacing: 4) {
                                    Text(reading.label).foregroundStyle(reading.color)
                                    Text(reading.value)
                                }
                            }
                        }
                    }.fixedSize()
                    VStack(alignment: .leading, spacing: 2) {
                        timestamp
                        ForEach(inspection.readings) { reading in
                            HStack(spacing: 6) {
                                Text(reading.label).foregroundStyle(reading.color)
                                Spacer(minLength: 0)
                                Text(reading.value)
                            }
                        }
                    }
                }
            } else {
                Text("Click or drag to inspect").foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .monospacedDigit().frame(maxWidth: .infinity, minHeight: 56)
        .accessibilityElement(children: .combine)
    }
}
