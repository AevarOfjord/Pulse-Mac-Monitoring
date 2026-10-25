import SwiftUI
import MonitorCore

struct InsightsPanel: View {
    @EnvironmentObject var monitor: MonitorStore
    var body: some View {
        Panel(title: "What’s limiting this Mac?", symbol: "lightbulb", color: Palette.amber) {
            if monitor.insights.isEmpty {
                Text(monitor.snapshot.cpu == nil ? "Collecting measurements…" : "No elevated resource signals in the latest sample.")
                    .font(.system(size: 13, weight: .medium))
                Text("Memory pressure, swap activity, CPU/GPU load, free storage, and thermal state are checked separately. A quiet sample cannot rule out brief slowdowns or limits outside these measurements.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            } else {
                ForEach(monitor.insights) { insight in
                    VStack(alignment: .leading, spacing: 7) {
                        Label(insight.title, systemImage: insight.severity == .critical ? "exclamationmark.octagon" : "exclamationmark.triangle")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.amber)
                        Text(insight.detail).font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button("Inspect apps & workloads") { monitor.selected = .processes }.buttonStyle(.link)
            }
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject var monitor: MonitorStore
    @ViewState private var range: Double = 900
    @ViewState private var metric = "Memory"
    @ViewState private var selectedDate: Date?
    private var temperatureGroup: TemperatureGroup? {
        switch metric {
        case "PMU die": return .pmu
        case "Battery": return .battery
        case "Storage temp": return .storage
        default: return nil
        }
    }
    private var chartMetric: ChartMetric {
        if let temperatureGroup { return .temperature(temperatureGroup) }
        switch metric {
        case "CPU": return .cpu
        case "GPU": return .gpu
        case "Download": return .download
        default: return .memory
        }
    }
    private var samples: [HistorySample] {
        monitor.historySamples.filter { $0.date >= Date().addingTimeInterval(-range) }
    }
    private var nearest: HistorySample? {
        guard let selectedDate else { return samples.last }
        return samples.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }
    var body: some View {
        VStack(spacing: 20) {
            Panel(title: "Resource history", subtitle: monitor.keepHistory ? "SAVED ON THIS MAC" : "THIS SESSION", symbol: "clock.arrow.circlepath",
                  inspection: chartMetric.inspection(in: samples, at: selectedDate, seconds: range)) {
                HStack {
                    Picker("Time range", selection: $range) {
                        Text("15 minutes").tag(900.0); Text("1 hour").tag(3600.0); Text("24 hours").tag(86400.0)
                    }.pickerStyle(.segmented)
                    Picker("Metric", selection: $metric) {
                        Text("Memory").tag("Memory"); Text("CPU").tag("CPU"); Text("GPU").tag("GPU"); Text("Download").tag("Download")
                        Text("PMU die °C").tag("PMU die"); Text("Battery °C").tag("Battery"); Text("Storage °C").tag("Storage temp")
                    }.frame(width: 175)
                }
                if samples.isEmpty { Text("History will appear as Pulse takes measurements.").foregroundStyle(Palette.muted).padding(.vertical, 45) }
                else {
                    TimeChart(history: samples, color: chartMetric.color, maximum: metric == "Download" || temperatureGroup != nil ? nil : 100,
                              unit: temperatureGroup != nil ? .celsius : metric == "Download" ? .rate : .percent,
                              seconds: range, value: { sample in
                        if let temperatureGroup { return sample.temperatures?.maximum(for: temperatureGroup) }
                        switch metric {
                        case "Memory": return sample.memory?.percent
                        case "GPU": return sample.gpu.utilization
                        case "Download": return sample.network?.incoming
                        default: return sample.cpu
                        }
                    }, selection: $selectedDate).frame(height: 200)
                    Slider(value: Binding(get: { selectedDate?.timeIntervalSince1970 ?? samples.last!.date.timeIntervalSince1970 },
                                          set: { selectedDate = Date(timeIntervalSince1970: $0) }),
                           in: samples.first!.date.timeIntervalSince1970...max(samples.first!.date.timeIntervalSince1970 + 1, samples.last!.date.timeIntervalSince1970)) {
                        Text("Inspect history time")
                    }
                }
                Text("Full resolution for the last 15 minutes; older data retains the last sample in each 30-second bucket for up to 24 hours. Charts display up to 240 observations, so short peaks can be omitted. Lines break across pauses, sleep, missing readings, and restarts. Quit clears session history unless local retention is enabled.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
            if let sample = nearest {
                Panel(title: "At \(sample.date.formatted(date: .abbreviated, time: .standard))", symbol: "scope") {
                    StatRow(label: "Memory pressure", value: sample.snapshot.memory?.pressure ?? "Unavailable")
                    StatRow(label: "Compressed / swap used", value: "\(sample.snapshot.memory.map { Format.bytes($0.compressed) } ?? "—") / \(sample.snapshot.memory?.swapUsed.map(Format.bytes) ?? "—")")
                    StatRow(label: "CPU / GPU", value: "\(Format.percent(sample.snapshot.cpu))% / \(Format.percent(sample.snapshot.gpu.utilization))%")
                    StatRow(label: "PMU die / battery / storage max", value: "\(Format.temperature(sample.snapshot.temperatures?.pmuMaximum)) / \(Format.temperature(sample.snapshot.temperatures?.batteryMaximum)) / \(Format.temperature(sample.snapshot.temperatures?.storageMaximum))")
                    Text("Largest group footprints at the nearest process scan\(sample.processesSampledAt.map { " (\($0.formatted(date: .omitted, time: .standard)))" } ?? "")")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    ForEach(Array(sample.contributors.enumerated()), id: \.offset) { _, contributor in
                        StatRow(label: contributor.name, value: contributor.footprint.map(Format.bytes) ?? "Unavailable")
                    }
                    if sample.contributors.isEmpty { Text("Process contributors unavailable.").font(.caption).foregroundStyle(Palette.muted) }
                }
            }
            Panel(title: "Sustained pressure events", subtitle: monitor.alertsEnabled ? "ALERTS ON" : "ALERTS OFF", symbol: "bell") {
                if monitor.events.isEmpty { Text("No sustained events recorded this session. Enable alerts in Settings to record events and optionally receive notifications.").font(.system(size: 11)).foregroundStyle(Palette.muted) }
                ForEach(monitor.events) { event in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(event.date.formatted(date: .omitted, time: .standard)) · \(event.insight.title)").font(.system(size: 12, weight: .medium))
                        Text(event.insight.detail).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                }
            }
        }
    }
}
