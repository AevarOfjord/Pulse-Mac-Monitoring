import SwiftUI
import MonitorCore

struct ProcessesView: View {
    @EnvironmentObject var monitor: MonitorStore
    @ViewState private var query = ""
    @ViewState private var sort = "CPU"
    private var filtered: [ProcessMetric] {
        let values = monitor.processes.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || String($0.pid).contains(query) }
        switch sort {
        case "Memory": return values.sorted { $0.memory > $1.memory }
        case "Name": return values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        default: return values.sorted { $0.cpu > $1.cpu }
        }
    }
    var body: some View {
        Panel(title: "Running processes", subtitle: "\(filtered.count) PROCESSES", symbol: "list.bullet.rectangle") {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                    TextField("Search by name or PID", text: $query).textFieldStyle(.plain)
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Clear search") }
                }.padding(10).background(Palette.background, in: RoundedRectangle(cornerRadius: 7))
                Picker("Sort by", selection: $sort) { Text("CPU").tag("CPU"); Text("Memory").tag("Memory"); Text("Name").tag("Name") }.frame(width: 160)
            }.font(.system(size: 12))
            ProcessList(processes: filtered)
            Text("CPU uses macOS ps accounting and can exceed 100% for a process using multiple cores. Memory is resident size (RSS), which includes shared pages. Refreshes every 5 seconds or the sampling interval, whichever is longer.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ProcessList: View {
    var processes: [ProcessMetric]
    var compact = false
    @ViewState private var selected: Int?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PROCESS"); Spacer()
                if !compact { Text("PID").frame(width: 64, alignment: .trailing) }
                Text("CPU").frame(width: 64, alignment: .trailing)
                Text("MEMORY").frame(width: 78, alignment: .trailing)
            }.font(.system(size: 8, weight: .semibold)).tracking(0.8).foregroundStyle(Palette.muted).padding(.bottom, 9)
            if processes.isEmpty {
                Text("No processes to display").font(.system(size: 12)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity).padding(.vertical, 35)
            }
            LazyVStack(spacing: 0) {
                ForEach(processes) { process in
                    VStack(alignment: .leading, spacing: 0) {
                        Button { if !compact { selected = selected == process.pid ? nil : process.pid } } label: {
                            HStack(spacing: 9) {
                                Image(systemName: process.path.contains(".app/") ? "app.fill" : "gearshape.fill")
                                    .font(.system(size: 11)).foregroundStyle(process.path.contains(".app/") ? Palette.blue : Palette.muted)
                                    .frame(width: 24, height: 24).background(Palette.border.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                                Text(process.name).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 5)
                                if !compact { Text(String(process.pid)).font(.system(size: 11)).foregroundStyle(Palette.muted).frame(width: 64, alignment: .trailing) }
                                Text("\(Format.percent(process.cpu))%")
                                    .font(.system(size: 11, weight: .medium)).foregroundStyle(process.cpu > 10 ? Palette.mint : .primary).frame(width: 64, alignment: .trailing)
                                Text(Format.bytes(process.memory)).font(.system(size: 11)).foregroundStyle(Palette.muted).frame(width: 78, alignment: .trailing)
                            }.monospacedDigit().frame(height: compact ? 34 : 42).contentShape(Rectangle())
                        }.buttonStyle(.plain).help(process.path)
                        if !compact && selected == process.pid {
                            Text(process.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                                .textSelection(.enabled).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Palette.background, in: RoundedRectangle(cornerRadius: 6)).padding(.bottom, 7)
                        }
                        Rectangle().fill(Palette.border.opacity(0.55)).frame(height: 0.5)
                    }
                }
            }
        }
    }
}
