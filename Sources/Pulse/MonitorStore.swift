import SwiftUI
import MonitorCore

struct HistoryPoint: Identifiable {
    let id = UUID()
    let date: Date
    let snapshot: SystemSnapshot
}

enum Section: String, CaseIterable, Identifiable {
    case overview = "Overview", cpu = "CPU", gpu = "GPU", memory = "Memory"
    case storage = "Storage", network = "Network", processes = "Processes"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .cpu: return "cpu"
        case .gpu: return "display"
        case .memory: return "memorychip"
        case .storage: return "internaldrive"
        case .network: return "network"
        case .processes: return "list.bullet.rectangle"
        }
    }
    var color: Color {
        switch self {
        case .overview, .cpu, .processes: return Palette.mint
        case .gpu: return Palette.purple
        case .memory: return Palette.blue
        case .storage: return Palette.amber
        case .network: return Palette.cyan
        }
    }
    var subtitle: String {
        switch self {
        case .overview: return "A little clarity on everything your Mac is doing."
        case .cpu: return "Processor activity, one core at a time."
        case .gpu: return "A closer look at your graphics workload."
        case .memory: return "See how your Mac is using its memory."
        case .storage: return "Space and activity on your drives."
        case .network: return "Live traffic across Ethernet and Wi-Fi."
        case .processes: return "Find the apps and services doing the work."
        }
    }
}

@MainActor final class MonitorStore: ObservableObject {
    @Published var snapshot = SystemSnapshot()
    @Published var history: [HistoryPoint] = []
    @Published var processes: [ProcessMetric] = []
    @Published var isPaused = false
    @Published var interval: Double = 2 { didSet { restart() } }
    @Published var selected: Section = .overview
    @Published var exportError: String?
    let hardware = SystemSampler.hardwareName()
    let sampler = SystemSampler()
    private var task: Task<Void, Never>?

    init() { restart() }
    func restart() {
        task?.cancel()
        guard !isPaused else { return }
        task = Task { [weak self] in
            guard let self else { return }
            await sampler.resetBaselines()
            var lastProcesses = Date.distantPast
            while !Task.isCancelled {
                let value = await sampler.sample()
                guard !Task.isCancelled else { break }
                snapshot = value
                history.append(HistoryPoint(date: value.timestamp, snapshot: value))
                history.removeAll { $0.date < value.timestamp.addingTimeInterval(-300) }
                if Date().timeIntervalSince(lastProcesses) >= 5 {
                    let values = await sampler.processes()
                    guard !Task.isCancelled else { break }
                    processes = values
                    lastProcesses = Date()
                }
                do { try await Task.sleep(for: .seconds(interval)) } catch { break }
            }
        }
    }
    func togglePause() { isPaused.toggle(); restart() }
    func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Pulse-\(Date().formatted(.iso8601.year().month().day())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(history.map(\.snapshot)).write(to: url, options: .atomic)
        } catch { exportError = error.localizedDescription }
    }
}
