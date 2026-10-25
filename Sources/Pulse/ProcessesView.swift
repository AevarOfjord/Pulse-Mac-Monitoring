import SwiftUI
import MonitorCore

struct ProcessesView: View {
    @EnvironmentObject var monitor: MonitorStore
    @ViewState private var query = ""
    @ViewState private var sort = UserDefaults.standard.string(forKey: "processSort") ?? "Footprint"
    @ViewState private var mode = UserDefaults.standard.string(forKey: "processMode") ?? "Apps & jobs"
    private var filtered: [ProcessMetric] {
        let values = monitor.processes.filter { matches($0.name) || String($0.pid).contains(query) }
        switch sort {
        case "CPU": return values.sorted { ($0.cpu ?? -1) > ($1.cpu ?? -1) }
        case "Name": return values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        default: return values.sorted { ($0.footprint ?? 0) > ($1.footprint ?? 0) }
        }
    }
    private func matches(_ text: String) -> Bool { query.isEmpty || text.localizedCaseInsensitiveContains(query) }
    private var groups: [ProcessGroup] {
        let values = monitor.groups.filter { (mode != "Workloads" || $0.kind == .workload) && (matches($0.name) || $0.members.contains { matches($0.name) || String($0.pid).contains(query) }) }
        switch sort {
        case "CPU": return values.sorted { ($0.cpu ?? -1) > ($1.cpu ?? -1) }
        case "Name": return values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        default: return values
        }
    }
    var body: some View {
        Panel(title: "Apps, workloads & processes", subtitle: "\(monitor.processes.count) PROCESSES", symbol: "list.bullet.rectangle") {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                    TextField("Search name, project or PID", text: $query).textFieldStyle(.plain)
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Clear search") }
                }.padding(10).background(Palette.background, in: RoundedRectangle(cornerRadius: 7))
                Picker("Sort by", selection: $sort) { Text("Footprint").tag("Footprint"); Text("CPU").tag("CPU"); Text("Name").tag("Name") }.frame(width: 175)
            }.font(.system(size: 12))
            Picker("Group processes", selection: $mode) {
                Text("Apps & jobs").tag("Apps & jobs"); Text("Workloads").tag("Workloads"); Text("All processes").tag("All processes")
            }.pickerStyle(.segmented)
            if mode == "All processes" { ProcessList(processes: filtered) }
            else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if groups.isEmpty { Text("No matching workloads or apps. Workloads are recognized from supported command categories and parent processes.").font(.caption).foregroundStyle(Palette.muted) }
                    ForEach(groups) { group in
                        DisclosureGroup {
                            ProcessList(processes: group.members).padding(.top, 14)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Label(group.name, systemImage: group.kind == .workload ? "terminal" : group.kind == .app ? "app" : "gearshape")
                                        .lineLimit(1).font(.system(size: 12, weight: .medium))
                                    Spacer()
                                    Text("\(Format.percent(group.cpu))% CPU").frame(width: 100, alignment: .trailing)
                                    Text(group.footprint.map(Format.bytes) ?? "Unavailable").frame(width: 90, alignment: .trailing)
                                }
                                Text("\(group.members.count) process\(group.members.count == 1 ? "" : "es") · root PID \(group.root.pid) · running \(Format.uptime(Date().timeIntervalSince(group.root.startedAt)))\(group.footprintIsPartial ? " · partial footprint" : " · footprint")")
                                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                            }
                        }.padding(12).background(Palette.background, in: RoundedRectangle(cornerRadius: 8))
                    }
                }.font(.system(size: 11)).monospacedDigit()
            }
            let duplicates = Dictionary(grouping: monitor.groups.filter { $0.kind == .workload }, by: \.name).filter { $0.value.count > 1 }
            if !duplicates.isEmpty {
                Label("Concurrent similar jobs: " + duplicates.keys.sorted().map { "\(duplicates[$0]!.count) × \($0)" }.joined(separator: "; ") + ". Check whether each run is still needed.", systemImage: "square.stack.3d.up")
                    .font(.system(size: 11)).foregroundStyle(Palette.amber)
            }
            Text("Physical footprint includes memory charged to a process, including compressed backing; it is different from resident memory (RSS). Group sums are approximate, may overlap shared allocations, and do not equal system RAM used. Per-process compressed bytes are available for Pulse itself; macOS restricts other tasks. CPU is measured between process scans and can exceed 100%. A dash means unavailable or warming up.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            Text("Last scan: \(monitor.processBatch.sampledAt.formatted(date: .omitted, time: .standard)) · \(String(format: "%.1f", monitor.processBatch.durationMilliseconds)) ms · every \(Int(monitor.processInterval))s · \(monitor.processBatch.unavailableCount) processes with restricted counters")
                .font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
        .onChange(of: sort) { _, value in UserDefaults.standard.set(value, forKey: "processSort") }
        .onChange(of: mode) { _, value in UserDefaults.standard.set(value, forKey: "processMode") }
    }
}

struct ProcessList: View {
    var processes: [ProcessMetric]
    var compact = false
    @ViewState private var selected: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PROCESS"); Spacer()
                if !compact { Text("PID").frame(width: 55, alignment: .trailing); Text("RSS").frame(width: 80, alignment: .trailing) }
                Text("CPU").frame(width: 65, alignment: .trailing)
                Text("FOOTPRINT").frame(width: 85, alignment: .trailing)
            }.font(.system(size: 8, weight: .semibold)).tracking(0.8).foregroundStyle(Palette.muted).padding(.bottom, 9)
            if processes.isEmpty { Text("No processes to display").font(.caption).foregroundStyle(Palette.muted).padding(30) }
            LazyVStack(spacing: 0) {
                ForEach(processes) { process in
                    VStack(alignment: .leading, spacing: 0) {
                        Button { if !compact { selected = selected == process.id ? nil : process.id } } label: {
                            HStack(spacing: 9) {
                                Image(systemName: process.appBundle != nil ? "app.fill" : "gearshape.fill").foregroundStyle(Palette.muted).frame(width: 16)
                                Text(process.name).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 0)
                                if !compact {
                                    Text(String(process.pid)).foregroundStyle(Palette.muted).frame(width: 55, alignment: .trailing)
                                    Text(process.residentMemory.map(Format.bytes) ?? "—").foregroundStyle(Palette.muted).frame(width: 80, alignment: .trailing)
                                }
                                Text(process.cpu.map { "\(Format.percent($0))%" } ?? "—").foregroundStyle(Palette.mint).frame(width: 65, alignment: .trailing)
                                Text(process.footprint.map(Format.bytes) ?? "—").frame(width: 85, alignment: .trailing)
                            }.font(.system(size: 11)).monospacedDigit().padding(.vertical, 10).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if !compact && selected == process.id {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(process.path.isEmpty ? "Executable path unavailable" : process.path).textSelection(.enabled)
                                Text("Parent PID \(process.parentPID) · started \(process.startedAt.formatted()) · running \(Format.uptime(Date().timeIntervalSince(process.startedAt)))")
                                Text("Peak footprint: \(process.peakFootprint.map(Format.bytes) ?? "Unavailable") · Compressed: \(process.compressedMemory.map(Format.bytes) ?? "Unavailable — task access restricted")")
                            }.font(.system(size: 10)).foregroundStyle(Palette.muted).padding(.bottom, 12).fixedSize(horizontal: false, vertical: true)
                        }
                        Rectangle().fill(Palette.border.opacity(0.6)).frame(height: 1)
                    }
                }
            }
        }
    }
}
