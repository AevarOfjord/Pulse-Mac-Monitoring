import SwiftUI
import MonitorCore

struct DashboardView: View {
    @EnvironmentObject var monitor: MonitorStore
    @ViewState private var selectedCPUDate: Date?
    @ViewState private var selectedGPUDate: Date?
    @ViewState private var selectedNetworkDate: Date?
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Palette.border).frame(width: 1)
            VStack(spacing: 0) {
                header
                if monitor.dashboardVisible { ScrollView {
                    VStack(spacing: 20) {
                        if !monitor.snapshot.errors.isEmpty {
                            Label(monitor.snapshot.errors.joined(separator: " "), systemImage: "exclamationmark.triangle")
                                .font(.system(size: 12)).foregroundStyle(Palette.amber).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if monitor.selected == .overview { overview }
                        else if monitor.selected == .processes { ProcessesView() }
                        else if monitor.selected == .history { HistoryView() }
                        else if monitor.selected == .temperatures { TemperaturesView() }
                        else { DetailView(section: monitor.selected) }
                    }.padding(.horizontal, 28).padding(.bottom, 24)
                }
                } else { Spacer() }
                footer
            }
        }
        .background(Palette.background)
        .background(DashboardWindowProbe(monitor: monitor).frame(width: 0, height: 0))
        .tint(Palette.mint)
        .onAppear { DispatchQueue.main.async { monitor.refreshWindowVisibility() } }
        .alert("Couldn’t export metrics", isPresented: Binding(get: { monitor.exportError != nil }, set: { if !$0 { monitor.exportError = nil } })) {
            Button("OK") { monitor.exportError = nil }
        } message: { Text(monitor.exportError ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "waveform.path.ecg").font(.system(size: 21, weight: .medium)).foregroundStyle(Palette.mint)
                    .frame(width: 36, height: 36).background(Palette.mint.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                Text("pulse").font(.system(size: 25, weight: .semibold, design: .rounded)).tracking(-0.7)
            }.padding(.horizontal, 22).padding(.top, 48).padding(.bottom, 36)
            Text("WORKSPACE").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Palette.muted).padding(.horizontal, 24).padding(.bottom, 13)
            ForEach(Section.allCases) { section in
                Button { monitor.selected = section } label: {
                    HStack(spacing: 12) {
                        Image(systemName: section.icon).font(.system(size: 14)).frame(width: 19)
                        Text(section.rawValue).font(.system(size: 12, weight: monitor.selected == section ? .semibold : .regular))
                        Spacer()
                        if monitor.selected == section { Capsule().fill(Palette.mint).frame(width: 3, height: 15) }
                    }
                    .foregroundStyle(monitor.selected == section ? Palette.mint : Palette.muted)
                    .padding(.horizontal, 13).frame(height: 40)
                    .background(monitor.selected == section ? Palette.mint.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.horizontal, 12).padding(.bottom, 5)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "laptopcomputer").font(.system(size: 25, weight: .light)).foregroundStyle(Palette.muted)
                Text(monitor.hardware).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                Text("\(ProcessInfo.processInfo.processorCount)-core CPU · \(Format.bytes(ProcessInfo.processInfo.physicalMemory)) RAM")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                HStack(spacing: 5) {
                    Circle().fill(Palette.mint).frame(width: 5, height: 5)
                    Text("On-device monitoring").font(.system(size: 9)).foregroundStyle(Palette.muted)
                }.padding(.top, 4)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 11)).padding(14)
            SettingsLink { Label("Settings", systemImage: "gearshape").font(.system(size: 12)) }.buttonStyle(.plain).padding(.horizontal, 24).padding(.bottom, 16)
            Text("PULSE FOR MAC  /  2.0").font(.system(size: 8, weight: .medium)).tracking(1.1).foregroundStyle(Palette.muted.opacity(0.6)).padding(.horizontal, 24).padding(.bottom, 21)
        }.frame(width: 198).background(Palette.sidebar)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("SYSTEM MONITOR").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(Palette.mint)
                Text(monitor.selected == .overview ? "System overview" : monitor.selected.rawValue)
                    .font(.system(size: 28, weight: .semibold)).tracking(-0.8)
                Text(monitor.selected.subtitle).font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                Circle().fill(monitor.isPaused ? Palette.amber : Palette.mint).frame(width: 6, height: 6)
                Text(monitor.isPaused ? "PAUSED" : "LIVE").font(.system(size: 9, weight: .semibold)).tracking(0.8)
            }.foregroundStyle(monitor.isPaused ? Palette.amber : Palette.mint)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background((monitor.isPaused ? Palette.amber : Palette.mint).opacity(0.08), in: Capsule())
            Picker("Refresh interval", selection: $monitor.interval) {
                Text("1 sec").tag(1.0); Text("2 sec").tag(2.0); Text("5 sec").tag(5.0)
            }.labelsHidden().frame(width: 86).help("Sampling interval")
            Button(action: monitor.togglePause) {
                Image(systemName: monitor.isPaused ? "play.fill" : "pause.fill").font(.system(size: 11)).frame(width: 28, height: 28)
            }.buttonStyle(.plain).background(Palette.panel, in: RoundedRectangle(cornerRadius: 7))
                .accessibilityLabel(monitor.isPaused ? "Resume sampling" : "Pause sampling")
                .help(monitor.isPaused ? "Resume sampling" : "Pause sampling")
            Button(action: monitor.export) {
                Image(systemName: "square.and.arrow.up").font(.system(size: 13)).frame(width: 28, height: 28)
            }.buttonStyle(.plain).background(Palette.panel, in: RoundedRectangle(cornerRadius: 7)).help("Export retained system metrics as JSON").accessibilityLabel("Export metrics")
        }.padding(.horizontal, 28).padding(.top, 36).padding(.bottom, 27)
    }

    private var overview: some View {
        VStack(spacing: 20) {
            InsightsPanel()
            TemperatureOverviewPanel()
            HStack(spacing: 14) {
                MetricCard(title: "CPU usage", icon: "cpu", value: Format.percent(monitor.snapshot.cpu), caption: "\(monitor.snapshot.cores.count) logical cores", color: Palette.mint, values: monitor.history.compactMap { $0.snapshot.cpu })
                MetricCard(title: "GPU usage", icon: "display", value: Format.percent(monitor.snapshot.gpu.utilization), caption: monitor.snapshot.gpu.utilization == nil ? "Not exposed by this Mac" : monitor.snapshot.gpu.name, color: Palette.purple, values: monitor.history.compactMap { $0.snapshot.gpu.utilization })
                MetricCard(title: "Memory", icon: "memorychip", value: Format.percent(monitor.snapshot.memory?.percent), caption: monitor.snapshot.memory.map { "\(Format.bytes($0.used)) of \(Format.bytes($0.total)) used" } ?? "Waiting for sample", color: Palette.blue, values: monitor.history.compactMap { $0.snapshot.memory?.percent })
                MetricCard(title: "Download", icon: "arrow.down", value: networkValue, unit: networkUnit, caption: "↑ \(Format.rate(monitor.snapshot.network?.outgoing)) upload", color: Palette.cyan, values: monitor.history.compactMap { $0.snapshot.network?.incoming })
            }
            HStack(alignment: .top, spacing: 18) {
                Panel(title: "CPU activity", subtitle: "LAST 2 MINUTES", symbol: "cpu",
                      inspection: ChartMetric.cpu.inspection(in: monitor.history, at: selectedCPUDate, seconds: 120)) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(Format.percent(monitor.snapshot.cpu)).font(.system(size: 29, weight: .medium, design: .rounded)).monospacedDigit()
                        Text("% total · \(monitor.isPaused ? "Paused" : "Live")").font(.system(size: 11)).foregroundStyle(Palette.muted)
                        Spacer()
                        DotLabel(text: "User", color: Palette.mint)
                        DotLabel(text: "System", color: Palette.blue)
                    }
                    TimeChart(history: monitor.history, color: Palette.mint, value: { $0.cpu == nil ? nil : $0.cpuUser }, secondary: { $0.cpu == nil ? nil : $0.cpuSystem }, selection: $selectedCPUDate).frame(height: 137)
                    HStack {
                        Text("\(Format.percent(monitor.snapshot.cpuUser))% user  ·  \(Format.percent(monitor.snapshot.cpuSystem))% system").font(.system(size: 10)).foregroundStyle(Palette.muted)
                        Spacer()
                        Text("\(Format.percent(monitor.snapshot.cpu.map { 100 - $0 }))% idle").font(.system(size: 10)).foregroundStyle(Palette.mint)
                    }
                }
                Panel(title: "GPU activity", subtitle: "LAST 2 MINUTES", symbol: "display", color: Palette.purple,
                      inspection: ChartMetric.gpu.inspection(in: monitor.history, at: selectedGPUDate, seconds: 120)) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(Format.percent(monitor.snapshot.gpu.utilization)).font(.system(size: 29, weight: .medium, design: .rounded)).monospacedDigit()
                        Text("% utilization").font(.system(size: 11)).foregroundStyle(Palette.muted)
                        Spacer()
                        DotLabel(text: "Device", color: Palette.purple)
                    }
                    TimeChart(history: monitor.history, color: Palette.purple, value: { $0.gpu.utilization }, selection: $selectedGPUDate).frame(height: 137)
                    Text(monitor.snapshot.gpu.utilization == nil ? "GPU counters are unavailable on this Mac." : "\(monitor.snapshot.gpu.name)  ·  \(monitor.snapshot.gpu.cores.map { "\($0) GPU cores" } ?? "Hardware accelerated")")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
            }
            HStack(alignment: .top, spacing: 18) {
                memoryPanel.frame(maxWidth: .infinity)
                Panel(title: "Top processes", subtitle: "PHYSICAL FOOTPRINT", symbol: "list.bullet.rectangle") {
                    ProcessList(processes: Array(monitor.processes.prefix(5)), compact: true)
                    Button { monitor.selected = .processes } label: {
                        HStack { Text("View all \(monitor.processes.count) processes"); Spacer(); Image(systemName: "arrow.up.right") }.font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.mint)
                    }.buttonStyle(.plain)
                }.frame(maxWidth: .infinity)
            }
            HStack(spacing: 18) {
                Panel(title: "Storage", symbol: "internaldrive", color: Palette.amber) {
                    UsageBar(fraction: monitor.snapshot.disk.percent / 100, color: Palette.amber)
                    StatRow(label: "Available", value: monitor.snapshot.disk.total > 0 ? Format.bytes(monitor.snapshot.disk.available) : "Unavailable")
                    StatRow(label: "Read / write", value: "\(Format.rate(monitor.snapshot.disk.activity?.incoming)) / \(Format.rate(monitor.snapshot.disk.activity?.outgoing))")
                }
                Panel(title: "Network activity", symbol: "network", color: Palette.cyan,
                      inspection: ChartMetric.network.inspection(in: monitor.history, at: selectedNetworkDate, seconds: 120)) {
                    HStack(spacing: 22) { DotLabel(text: "Download", color: Palette.cyan); DotLabel(text: "Upload", color: Palette.blue) }
                    TimeChart(history: monitor.history, color: Palette.cyan, maximum: nil, unit: .rate, value: { $0.network?.incoming }, secondary: { $0.network?.outgoing }, selection: $selectedNetworkDate).frame(height: 64)
                }
            }
        }
    }

    private var memoryPanel: some View {
        Panel(title: "Memory breakdown", symbol: "memorychip", color: Palette.blue) {
            if let memory = monitor.snapshot.memory {
                HStack(alignment: .firstTextBaseline) {
                    Text(Format.bytes(memory.used)).font(.system(size: 25, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("/ \(Format.bytes(memory.total))").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Spacer()
                    Text(memory.pressure).font(.system(size: 9, weight: .medium)).foregroundStyle(memory.pressure == "Normal" ? Palette.mint : Palette.amber)
                        .padding(.horizontal, 8).padding(.vertical, 5).background(Palette.border.opacity(0.5), in: Capsule())
                }
                MemoryBar(memory: memory).frame(height: 10)
                VStack(spacing: 11) {
                    memoryRow("App memory", bytes: memory.app, color: Palette.blue)
                    memoryRow("Wired", bytes: memory.wired, color: Palette.purple)
                    memoryRow("Compressed", bytes: memory.compressed, color: Palette.cyan)
                    memoryRow("Available", bytes: memory.available, color: Palette.muted)
                }
            } else { Text("Waiting for memory statistics…").foregroundStyle(Palette.muted) }
        }
    }
    private func memoryRow(_ label: String, bytes: UInt64, color: Color) -> some View {
        HStack { DotLabel(text: label, color: color); Spacer(); Text(Format.bytes(bytes)).font(.system(size: 11)).monospacedDigit() }
    }
    private var networkValue: String {
        guard let rate = monitor.snapshot.network?.incoming else { return "—" }
        return String(format: "%.1f", rate / (rate >= 1_048_576 ? 1_048_576 : 1024))
    }
    private var networkUnit: String { (monitor.snapshot.network?.incoming ?? 0) >= 1_048_576 ? "MB/s" : "KB/s" }
    private var footer: some View {
        HStack(spacing: 16) {
            HStack(spacing: 5) {
                Image(systemName: "thermometer.medium").foregroundStyle(monitor.snapshot.thermal == "Nominal" ? Palette.mint : Palette.amber)
                Text("Thermal: \(monitor.snapshot.thermal)")
            }
            Text("Uptime \(Format.uptime(monitor.snapshot.uptime))")
            Spacer()
            Text(monitor.isPaused ? "Sampling paused" : "Updated \(monitor.snapshot.timestamp.formatted(date: .omitted, time: .standard))")
        }.font(.system(size: 9)).foregroundStyle(Palette.muted).padding(.horizontal, 28).frame(height: 35)
            .overlay(alignment: .top) { Rectangle().fill(Palette.border).frame(height: 1) }
    }
}

struct MemoryBar: View {
    var memory: MemoryMetrics
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                Rectangle().fill(Palette.blue).frame(width: width(memory.app, geometry))
                Rectangle().fill(Palette.purple).frame(width: width(memory.wired, geometry))
                Rectangle().fill(Palette.cyan).frame(width: width(memory.compressed, geometry))
                Rectangle().fill(Palette.border)
            }.clipShape(Capsule())
        }.accessibilityLabel("Memory: \(Format.percent(memory.percent)) percent used")
    }
    private func width(_ bytes: UInt64, _ geometry: GeometryProxy) -> CGFloat {
        memory.total > 0 ? max(0, geometry.size.width - 6) * min(1, Double(bytes) / Double(memory.total)) : 0
    }
}
