import SwiftUI
import MonitorCore

private let temperatureGroups: [TemperatureGroup] = [.pmu, .battery, .storage]

struct TemperatureOverviewPanel: View {
    @EnvironmentObject var monitor: MonitorStore
    var body: some View {
        Panel(title: "Temperatures", subtitle: monitor.isPaused ? "PAUSED" : "~5-SECOND READINGS", symbol: "thermometer.medium", color: Palette.amber) {
            TemperatureSummaryView(summary: monitor.snapshot.temperatures)
            HStack {
                Text("Highest valid sensor in each group · macOS thermal state: \(monitor.snapshot.thermal)")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                Spacer()
                Button("View sensors") { monitor.selected = .temperatures }.buttonStyle(.link)
            }
        }
    }
}

struct TemperatureSummaryView: View {
    let summary: TemperatureSummary?
    var body: some View {
        HStack(spacing: 28) {
            ForEach(temperatureGroups, id: \.self) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.title + " max").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Text(Format.temperature(summary?.maximum(for: group)))
                        .font(.system(size: 25, weight: .medium, design: .rounded)).monospacedDigit()
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.accessibilityElement(children: .combine)
    }
}

struct TemperaturesView: View {
    @EnvironmentObject var monitor: MonitorStore
    @ViewState private var group: TemperatureGroup = .pmu
    @ViewState private var selectedDate: Date?
    @ViewState private var window: Double = 120
    private var report: TemperatureReport { monitor.temperatures }
    private var status: String {
        switch report.availability {
        case .notSampled: return "Waiting for the first temperature reading…"
        case .available: return "\(report.readings.count) valid sensors · \(report.rejectedCount) unavailable or invalid readings omitted"
        case .unavailable: return "This Mac is not exposing valid temperature readings."
        case .unsupported: return "Temperature access is unavailable on this macOS version."
        }
    }
    var body: some View {
        VStack(spacing: 20) {
            Panel(title: "Hardware temperatures", subtitle: monitor.isPaused ? "PAUSED" : "ABOUT EVERY 5 SECONDS", symbol: "thermometer.medium", color: Palette.amber) {
                TemperatureSummaryView(summary: monitor.snapshot.temperatures)
                StatRow(label: "macOS thermal state", value: monitor.snapshot.thermal)
                if let date = report.sampledAt {
                    StatRow(label: "Sensors read at", value: date.formatted(date: .omitted, time: .standard))
                }
                Text(status).font(.system(size: 11)).foregroundStyle(Palette.muted)
                Text("PMU die is the highest reading among the hardware’s PMU tdie zones; it is not a verified CPU or GPU core temperature. Battery and storage show the highest sensor with a battery or NAND label. Thermal state is macOS’s separate severity assessment.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
            Panel(title: "Temperature history", symbol: "chart.xyaxis.line", color: Palette.amber,
                  inspection: ChartMetric.temperature(group).inspection(in: monitor.history, at: selectedDate, seconds: window)) {
                HStack {
                    Picker("Temperature group", selection: $group) {
                        ForEach(temperatureGroups, id: \.self) { group in Text(group.title).tag(group) }
                    }.pickerStyle(.segmented).labelsHidden()
                    Picker("Temperature history range", selection: $window) {
                        Text("1 min").tag(60.0); Text("2 min").tag(120.0); Text("5 min").tag(300.0)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 210)
                }
                if !monitor.history.contains(where: { $0.snapshot.temperatures?.maximum(for: group) != nil }) {
                    Text("No readings for this sensor group in the current history.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                TimeChart(history: monitor.history, color: Palette.amber, maximum: nil, unit: .celsius, seconds: window,
                          value: { $0.temperatures?.maximum(for: group) }, selection: $selectedDate).frame(height: 190)
            }
            Panel(title: "Available sensors", subtitle: "ORIGINAL HARDWARE LABELS", symbol: "sensor", color: Palette.amber) {
                if report.readings.isEmpty {
                    Text(status).font(.system(size: 12)).foregroundStyle(Palette.muted)
                } else {
                    ForEach(TemperatureGroup.allCases, id: \.self) { category in
                        let readings = report.readings.filter { $0.group == category }
                        if !readings.isEmpty {
                            Text(category.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.amber)
                            ForEach(Array(readings.enumerated()), id: \.element.id) { index, reading in
                                StatRow(label: sensorLabel(reading, in: readings, index: index), value: Format.temperature(reading.celsius))
                            }
                        }
                    }
                }
                Text("Sensor availability and labels vary by chip and macOS version. Pulse reads local HID thermal events without administrator access. Missing and implausible values are omitted; repeated hardware labels can represent distinct sensors. History and exports store group maxima, rather than this full sensor list.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func sensorLabel(_ reading: TemperatureReading, in readings: [TemperatureReading], index: Int) -> String {
        guard readings.filter({ $0.name == reading.name }).count > 1 else { return reading.name }
        let ordinal = readings.prefix(index + 1).filter { $0.name == reading.name }.count
        return "\(reading.name) · sensor \(ordinal)"
    }
}
