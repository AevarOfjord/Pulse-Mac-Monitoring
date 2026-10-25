import SwiftUI
import MonitorCore

@main struct PulseApp: App {
    @StateObject private var monitor = MonitorStore()
    var body: some Scene {
        WindowGroup("Pulse", id: "dashboard") {
            DashboardView().environmentObject(monitor)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1060, minHeight: 730)
        }
        .defaultSize(width: 1320, height: 920)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Export Metrics…", action: monitor.export).keyboardShortcut("e", modifiers: [.command, .shift])
            }
            CommandMenu("Monitor") {
                Button(monitor.isPaused ? "Resume Sampling" : "Pause Sampling", action: monitor.togglePause)
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                ForEach(Section.allCases) { section in
                    Button(section.rawValue) { monitor.selected = section }
                }
            }
        }
        MenuBarExtra {
            MenuBarView().environmentObject(monitor)
        } label: {
            Image(systemName: "waveform.path.ecg")
            Text("\(Format.percent(monitor.snapshot.cpu))%")
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarView: View {
    @EnvironmentObject var monitor: MonitorStore
    @Environment(\.openWindow) var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Label("Pulse", systemImage: "waveform.path.ecg").font(.headline); Spacer(); Text(monitor.isPaused ? "Paused" : "Live").foregroundStyle(Palette.mint) }
            menuRow("CPU", value: "\(Format.percent(monitor.snapshot.cpu))%", color: Palette.mint)
            menuRow("GPU", value: monitor.snapshot.gpu.utilization.map { "\(Format.percent($0))%" } ?? "Unavailable", color: Palette.purple)
            menuRow("Memory", value: monitor.snapshot.memory.map { "\(Format.bytes($0.used)) / \(Format.bytes($0.total))" } ?? "Unavailable", color: Palette.blue)
            Divider()
            Button("Open Dashboard") { openWindow(id: "dashboard"); NSApp.activate(ignoringOtherApps: true) }
            Button(monitor.isPaused ? "Resume Sampling" : "Pause Sampling", action: monitor.togglePause)
            Button("Quit Pulse") { NSApp.terminate(nil) }
        }.padding(20).frame(width: 290).preferredColorScheme(.dark)
    }
    private func menuRow(_ title: String, value: String, color: Color) -> some View {
        HStack { Circle().fill(color).frame(width: 6, height: 6); Text(title); Spacer(); Text(value).monospacedDigit().foregroundStyle(.secondary) }.font(.system(size: 12))
    }
}
