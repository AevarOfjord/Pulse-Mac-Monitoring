import SwiftUI
import MonitorCore

struct DetailView: View {
    @EnvironmentObject var monitor: MonitorStore
    let section: Section
    @ViewState private var window: Double = 120
    @ViewState private var selectedDate: Date?
    private var chartMetric: ChartMetric {
        switch section {
        case .gpu: return .gpu
        case .memory: return .memory
        case .storage: return .storage
        case .network: return .network
        default: return .cpu
        }
    }
    private var snapshot: SystemSnapshot { monitor.snapshot }
    var body: some View {
        VStack(spacing: 20) {
            Panel(title: "\(section.rawValue) history", symbol: section.icon, color: section.color,
                  inspection: chartMetric.inspection(in: monitor.history, at: selectedDate, seconds: window)) {
                HStack(alignment: .firstTextBaseline) {
                    Text(headline).font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit()
                    Spacer()
                    Picker("History", selection: $window) { Text("1 min").tag(60.0); Text("2 min").tag(120.0); Text("5 min").tag(300.0) }.pickerStyle(.segmented).frame(width: 210)
                }
                TimeChart(history: monitor.history, color: section.color, maximum: isRate ? nil : 100, unit: isRate ? .rate : .percent, seconds: window,
                          value: primaryValue, secondary: isRate ? secondaryValue : nil, selection: $selectedDate).frame(height: 250)
                if isRate {
                    HStack(spacing: 20) { DotLabel(text: section == .network ? "Download" : "Read", color: section.color); DotLabel(text: section == .network ? "Upload" : "Write", color: Palette.blue) }
                }
            }
            switch section {
            case .cpu: cpu
            case .gpu: gpu
            case .memory: memory
            case .storage: storage
            case .network: network
            default: EmptyView()
            }
        }
    }
    private var isRate: Bool { section == .network || section == .storage }
    private func primaryValue(_ sample: SystemSnapshot) -> Double? {
        switch section {
        case .cpu: return sample.cpu
        case .gpu: return sample.gpu.utilization
        case .memory: return sample.memory?.percent
        case .storage: return sample.disk.activity?.incoming
        case .network: return sample.network?.incoming
        default: return nil
        }
    }
    private func secondaryValue(_ sample: SystemSnapshot) -> Double? {
        section == .network ? sample.network?.outgoing : sample.disk.activity?.outgoing
    }
    private var headline: String {
        isRate ? Format.rate(primaryValue(snapshot)) : primaryValue(snapshot).map { "\(Format.percent($0))%" } ?? "Unavailable"
    }
    private var cpu: some View {
        VStack(spacing: 20) {
            Panel(title: "Logical cores", subtitle: "\(snapshot.cores.count) CORES", symbol: "cpu") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 20)], spacing: 22) {
                    ForEach(Array(snapshot.cores.enumerated()), id: \.offset) { index, value in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Text("Core \(index + 1)").foregroundStyle(Palette.muted); Spacer(); Text("\(Int(value))%") }.font(.system(size: 10)).monospacedDigit()
                            UsageBar(fraction: value / 100, color: Palette.mint)
                        }
                    }
                }
            }
            Panel(title: "Processor details", symbol: "info.circle") {
                StatRow(label: "Processor", value: monitor.hardware)
                StatRow(label: "User / system", value: "\(Format.percent(snapshot.cpuUser))% / \(Format.percent(snapshot.cpuSystem))%")
                StatRow(label: "Load average · 1 / 5 / 15 minutes", value: snapshot.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: " / "))
                StatRow(label: "Thermal state", value: snapshot.thermal)
            }
        }
    }
    private var gpu: some View {
        Panel(title: "Graphics processor", symbol: "display", color: Palette.purple) {
            StatRow(label: "Device", value: snapshot.gpu.name)
            StatRow(label: "GPU cores", value: snapshot.gpu.cores.map(String.init) ?? "Unavailable")
            StatRow(label: "Renderer utilization", value: snapshot.gpu.renderer.map { "\(Format.percent($0))%" } ?? "Unavailable")
            StatRow(label: "Tiler utilization", value: snapshot.gpu.tiler.map { "\(Format.percent($0))%" } ?? "Unavailable")
            StatRow(label: "GPU memory in use", value: snapshot.gpu.memoryUsed.map(Format.bytes) ?? "Unavailable")
            Text("These readings come from the GPU driver. Availability varies by Mac and macOS version. On Macs with multiple GPUs, Pulse shows the busiest available accelerator. See Temperatures for available thermal zones; these are not mapped to individual CPU or GPU cores.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var memory: some View {
        Panel(title: "Physical memory", symbol: "memorychip", color: Palette.blue) {
            if let memory = snapshot.memory {
                MemoryBar(memory: memory).frame(height: 14)
                StatRow(label: "Installed", value: Format.bytes(memory.total))
                StatRow(label: "App memory", value: Format.bytes(memory.app), color: Palette.blue)
                StatRow(label: "Wired", value: Format.bytes(memory.wired), color: Palette.purple)
                StatRow(label: "Compressed", value: Format.bytes(memory.compressed), color: Palette.cyan)
                StatRow(label: "Cached files (reclaimable)", value: Format.bytes(memory.cached))
                StatRow(label: "Available (includes reclaimable memory)", value: Format.bytes(memory.available))
                StatRow(label: "Swap used", value: memory.swapUsed.map(Format.bytes) ?? "Unavailable")
                StatRow(label: "Swap read / write", value: "\(Format.rate(memory.swapActivity?.incoming)) / \(Format.rate(memory.swapActivity?.outgoing))")
                StatRow(label: "Memory pressure", value: memory.pressure, color: memory.pressure == "Normal" ? Palette.mint : Palette.amber)
            } else { Text("Memory statistics are unavailable.").foregroundStyle(Palette.muted) }
        }
    }
    private var storage: some View {
        Panel(title: "Startup disk", symbol: "internaldrive", color: Palette.amber) {
            UsageBar(fraction: snapshot.disk.percent / 100, color: Palette.amber)
            StatRow(label: "Capacity", value: snapshot.disk.total > 0 ? Format.bytes(snapshot.disk.total) : "Unavailable")
            StatRow(label: "Used", value: snapshot.disk.total > 0 ? Format.bytes(snapshot.disk.used) : "Unavailable")
            StatRow(label: "Available", value: snapshot.disk.total > 0 ? Format.bytes(snapshot.disk.available) : "Unavailable")
            StatRow(label: "Read speed · all block storage", value: Format.rate(snapshot.disk.activity?.incoming))
            StatRow(label: "Write speed · all block storage", value: Format.rate(snapshot.disk.activity?.outgoing))
            Text("Capacity reflects the APFS data volume. Read and write rates include all block storage drivers that expose counters. Available space excludes purgeable files and may differ from Finder.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var network: some View {
        VStack(spacing: 20) {
            ForEach(snapshot.interfaces) { interface in
                Panel(title: interface.name, symbol: "network", color: Palette.cyan) {
                    StatRow(label: "Download", value: Format.rate(interface.rate?.incoming), color: Palette.cyan)
                    StatRow(label: "Upload", value: Format.rate(interface.rate?.outgoing), color: Palette.blue)
                    StatRow(label: "Received · interface lifetime", value: Format.bytes(interface.received))
                    StatRow(label: "Sent · interface lifetime", value: Format.bytes(interface.sent))
                }
            }
            Text(snapshot.interfaces.isEmpty ? "No active Ethernet or Wi-Fi interfaces were found." : "Traffic is summed across active en* interfaces (Ethernet and Wi-Fi). VPN, loopback, and peer-to-peer interfaces are excluded to avoid counting the same traffic twice. This measures traffic, not your connection’s maximum speed.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
