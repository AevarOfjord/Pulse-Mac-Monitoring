import SwiftUI
import MonitorCore
import ServiceManagement
import UserNotifications

typealias HistoryPoint = HistorySample

enum Section: String, CaseIterable, Identifiable {
    case overview = "Overview", cpu = "CPU", gpu = "GPU", memory = "Memory"
    case temperatures = "Temperatures", storage = "Storage", network = "Network", processes = "Processes", history = "History"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .cpu: return "cpu"
        case .gpu: return "display"
        case .memory: return "memorychip"
        case .temperatures: return "thermometer.medium"
        case .storage: return "internaldrive"
        case .network: return "network"
        case .processes: return "list.bullet.rectangle"
        case .history: return "clock.arrow.circlepath"
        }
    }
    var color: Color {
        switch self {
        case .overview, .cpu, .processes, .history: return Palette.mint
        case .gpu: return Palette.purple
        case .memory: return Palette.blue
        case .storage, .temperatures: return Palette.amber
        case .network: return Palette.cyan
        }
    }
    var subtitle: String {
        switch self {
        case .overview: return "A little clarity on everything your Mac is doing."
        case .cpu: return "Processor activity, one core at a time."
        case .gpu: return "A closer look at your graphics workload."
        case .memory: return "See how your Mac is using its memory."
        case .temperatures: return "Hardware sensor readings in degrees Celsius."
        case .storage: return "Space and activity on your drives."
        case .network: return "Live traffic across Ethernet and Wi-Fi."
        case .processes: return "Find the apps and services doing the work."
        case .history: return "Look back at pressure, activity, and the largest workloads."
        }
    }
}

@MainActor final class MonitorStore: ObservableObject {
    @Published var snapshot = SystemSnapshot()
    @Published var temperatures = TemperatureReport()
    @Published var history: [HistoryPoint] = []
    @Published var processes: [ProcessMetric] = []
    @Published var groups: [ProcessGroup] = []
    @Published var insights: [ResourceInsight] = []
    @Published var events: [AlertEvent] = []
    @Published var processBatch = ProcessBatch()
    @Published var dashboardVisible = true
    @Published var isPaused = false
    @Published var interval: Double { didSet { defaults.set(interval, forKey: "interval"); restart() } }
    @Published var adaptive: Bool { didSet { defaults.set(adaptive, forKey: "adaptive") } }
    @Published var menuMetric: String { didSet { defaults.set(menuMetric, forKey: "menuMetric") } }
    @Published var keepHistory: Bool { didSet { defaults.set(keepHistory, forKey: "keepHistory"); restart() } }
    @Published var alertsEnabled: Bool { didSet { defaults.set(alertsEnabled, forKey: "alerts"); alertEngine.resetContinuity() } }
    @Published var alertDuration: Double { didSet { defaults.set(alertDuration, forKey: "alertDuration"); alertEngine.resetContinuity() } }
    @Published var settingsError: String?
    @Published var notificationStatus = "Not requested"
    @Published var notificationTestStatus: String?
    @Published var loginEnabled = false
    @Published var loginStatus = "Off"
    @Published var selected: Section = .overview
    @Published var exportError: String?
    let hardware = SystemSampler.hardwareName()
    let sampler = SystemSampler()
    private let defaults = UserDefaults.standard
    private let disk: HistoryDisk
    private var buffer = HistoryBuffer()
    private var alertEngine = SustainedAlertEngine()
    private var sleeping = false
    private var loadedHistory = false
    private var observers: [NSObjectProtocol] = []
    private let dashboardWindows = NSHashTable<NSWindow>.weakObjects()
    private var task: Task<Void, Never>?
    var historySamples: [HistorySample] { buffer.samples }
    var effectiveInterval: Double { adaptive && !dashboardVisible ? max(5, interval) : interval }
    var processInterval: Double { adaptive && !dashboardVisible ? 15 : max(5, interval) }
    var menuText: String {
        if isPaused { return "Paused" }
        switch menuMetric {
        case "Memory": return snapshot.memory.map { "\(Int($0.percent))% RAM" } ?? "— RAM"
        case "GPU": return "\(Format.percent(snapshot.gpu.utilization))% GPU"
        case "Network": return "↓ \(Format.rate(snapshot.network?.incoming))"
        default: return "\(Format.percent(snapshot.cpu))%"
        }
    }

    init() {
        let savedInterval = UserDefaults.standard.double(forKey: "interval")
        interval = [1, 2, 5].contains(savedInterval) ? savedInterval : 2
        adaptive = UserDefaults.standard.object(forKey: "adaptive") as? Bool ?? true
        menuMetric = UserDefaults.standard.string(forKey: "menuMetric") ?? "CPU"
        keepHistory = UserDefaults.standard.bool(forKey: "keepHistory")
        alertsEnabled = UserDefaults.standard.bool(forKey: "alerts")
        let duration = UserDefaults.standard.double(forKey: "alertDuration")
        alertDuration = [30, 60, 120].contains(duration) ? duration : 60
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        disk = HistoryDisk(url: support.appendingPathComponent("Pulse/history-v2.json"))
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleeping = true; self?.restart() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleeping = false; self?.restart() }
        })
        for name in [NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification, NSWindow.didBecomeKeyNotification,
                     NSApplication.didHideNotification, NSApplication.didUnhideNotification, NSApplication.didBecomeActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.refreshWindowVisibility()
                    if name == NSApplication.didBecomeActiveNotification || name == NSWindow.didBecomeKeyNotification {
                        self.refreshLoginStatus()
                        await self.refreshNotificationStatus()
                    }
                }
            })
        }
        refreshLoginStatus()
        Task { await refreshNotificationStatus() }
        restart()
    }
    func refreshWindowVisibility() {
        let visible = !NSApp.isHidden && dashboardWindows.allObjects.contains { $0.isVisible && !$0.isMiniaturized }
        if dashboardVisible != visible { dashboardVisible = visible }
    }
    func trackDashboardWindow(_ window: NSWindow) {
        dashboardWindows.add(window)
        refreshWindowVisibility()
    }
    func restart() {
        task?.cancel()
        alertEngine.resetContinuity(); buffer.breakContinuity()
        task = Task { [weak self] in
            guard let self else { return }
            if keepHistory && !loadedHistory {
                do { let saved = try await disk.load(); guard !Task.isCancelled else { return }; buffer.restore(saved + buffer.samples); loadedHistory = true }
                catch { settingsError = "Couldn’t load local history: \(error.localizedDescription)"; loadedHistory = true }
            } else if !keepHistory {
                do { try await disk.clear() } catch { settingsError = error.localizedDescription }
            }
            guard !Task.isCancelled, !isPaused, !sleeping else { return }
            await sampler.resetBaselines()
            var lastProcesses = Date.distantPast
            var lastSave = Date.distantPast
            while !Task.isCancelled {
                let value = await sampler.sample()
                guard !Task.isCancelled else { break }
                snapshot = value
                let report = await sampler.temperatureReport()
                guard !Task.isCancelled else { break }
                if report.sampledAt != temperatures.sampledAt { temperatures = report }
                refreshWindowVisibility()
                if Date().timeIntervalSince(lastProcesses) >= processInterval {
                    let batch = await sampler.processes()
                    guard !Task.isCancelled else { break }
                    processBatch = batch; processes = batch.processes; groups = ProcessGrouping.groups(processes)
                    lastProcesses = Date()
                }
                insights = InsightAnalyzer.analyze(value, groups: groups)
                let contributors = groups.filter { $0.footprint != nil }.prefix(5).map { Contributor(name: $0.name, footprint: $0.footprint, cpu: $0.cpu) }
                buffer.append(value, contributors: contributors, processesSampledAt: processes.isEmpty ? nil : processBatch.sampledAt)
                if dashboardVisible { history = buffer.samples.filter { $0.date >= value.timestamp.addingTimeInterval(-300) } }
                if alertsEnabled {
                    for insight in alertEngine.evaluate(insights, uptime: value.uptime, duration: alertDuration, maximumGap: max(30, effectiveInterval * 3)) {
                        events.insert(AlertEvent(date: value.timestamp, insight: insight), at: 0)
                        if events.count > 100 { events.removeLast() }
                        await sendNotification(insight)
                    }
                }
                if keepHistory && Date().timeIntervalSince(lastSave) >= 60 {
                    do { try await disk.save(buffer.samples); lastSave = Date() }
                    catch { settingsError = "Couldn’t save local history: \(error.localizedDescription)" }
                }
                do { try await Task.sleep(for: .seconds(effectiveInterval)) } catch { break }
            }
        }
    }
    func togglePause() { isPaused.toggle(); restart() }
    func clearHistory() {
        buffer = HistoryBuffer(); history = []; events = []; alertEngine.resetContinuity()
        task?.cancel()
        Task {
            do { try await disk.clear() } catch { settingsError = error.localizedDescription }
            restart()
        }
    }
    func setAlerts(_ enabled: Bool) {
        alertsEnabled = enabled
        guard enabled else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings()
            if status.authorizationStatus == .notDetermined {
                do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
                catch { settingsError = "Notification authorization: \(error.localizedDescription)" }
            }
            await refreshNotificationStatus()
        }
    }
    func refreshNotificationStatus() async {
        let status = await UNUserNotificationCenter.current().notificationSettings()
        let value = status.authorizationStatus == .authorized ? "Allowed" : status.authorizationStatus == .denied ? "Blocked in System Settings; events still appear in History" : "Not requested"
        if value != notificationStatus { notificationTestStatus = nil; notificationStatus = value }
    }
    private func sendNotification(_ insight: ResourceInsight) async {
        await refreshNotificationStatus()
        guard notificationStatus == "Allowed" else { return }
        do {
            try await deliverNotification(title: "Pulse · \(insight.title)", body: "Sustained for at least \(Int(alertDuration)) seconds. Open Pulse to inspect the measurements.")
        } catch { settingsError = "Couldn’t deliver notification: \(error.localizedDescription)" }
    }
    func testNotification() {
        Task {
            await refreshNotificationStatus()
            guard notificationStatus == "Allowed" else { settingsError = "Allow Pulse notifications in System Settings first."; return }
            do {
                try await deliverNotification(title: "Pulse · Test notification", body: "Notifications are working. Resource alerts require a sustained elevated signal.")
                notificationTestStatus = "Test notification requested. macOS controls banner delivery and Focus settings."
            } catch { settingsError = "Couldn’t deliver test notification: \(error.localizedDescription)" }
        }
    }
    private func deliverNotification(title: String, body: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        // Notifications deliberately exclude app and project names on the lock screen.
        content.body = body
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
    func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        loginEnabled = status == .enabled
        loginStatus = status == .enabled ? "On" : status == .requiresApproval ? "Needs approval in System Settings → Login Items" : "Off"
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { settingsError = "Login item: \(error.localizedDescription). Install Pulse in Applications first." }
        refreshLoginStatus()
    }
    func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Pulse-\(Date().formatted(.iso8601.year().month().day())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(buffer.samples.map(\.snapshot)).write(to: url, options: .atomic)
        } catch { exportError = error.localizedDescription }
    }
}

struct AlertEvent: Identifiable {
    let id = UUID()
    let date: Date
    let insight: ResourceInsight
}
