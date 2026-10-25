import Foundation

public struct ResourceInsight: Identifiable, Sendable, Codable {
    public enum Resource: String, Codable, Sendable { case memory, cpu, gpu, thermal, storage }
    public enum Severity: Int, Codable, Sendable { case information, warning, critical }
    public var id: String { resource.rawValue }
    public let resource: Resource
    public let severity: Severity
    public let title: String
    public let detail: String
    public init(resource: Resource, severity: Severity, title: String, detail: String) {
        self.resource = resource; self.severity = severity; self.title = title; self.detail = detail
    }
}

public enum InsightAnalyzer {
    public static func analyze(_ sample: SystemSnapshot, groups: [ProcessGroup]) -> [ResourceInsight] {
        var result: [ResourceInsight] = []
        if let memory = sample.memory {
            let swapping = (memory.swapActivity?.incoming ?? 0) + (memory.swapActivity?.outgoing ?? 0)
            if memory.pressure == "Warning" || memory.pressure == "Critical" || swapping >= 20 * 1_048_576 {
                let largest = groups.filter { $0.footprint != nil }.prefix(2).map {
                    "\($0.name): \(Format.bytes($0.footprint!))\($0.footprintIsPartial ? " (partial)" : "")"
                }.joined(separator: "; ")
                result.append(ResourceInsight(resource: .memory, severity: memory.pressure == "Critical" ? .critical : .warning,
                    title: "Memory is under pressure",
                    detail: "macOS pressure: \(memory.pressure). Swap I/O: \(Format.rate(memory.swapActivity.map { $0.incoming + $0.outgoing })). " +
                        (largest.isEmpty ? "Process footprints are unavailable." : "Largest reported footprints: \(largest). ") +
                        "Inspect these workloads before starting more jobs; size alone does not prove the cause."))
            }
        }
        if let cpu = sample.cpu, cpu >= 85 {
            let busy = groups.sorted { ($0.cpu ?? 0) > ($1.cpu ?? 0) }.prefix(2).filter { $0.cpu != nil }
                .map { "\($0.name) \(Format.percent($0.cpu))%" }.joined(separator: "; ")
            result.append(ResourceInsight(resource: .cpu, severity: .warning, title: "CPU capacity is busy",
                detail: "Whole-machine CPU is \(Format.percent(cpu))%. " + (busy.isEmpty ? "Process deltas are warming up." : "Busiest groups: \(busy). Process CPU can exceed 100% across cores.") + " Consider running fewer concurrent compute jobs."))
        }
        if let gpu = sample.gpu.utilization, gpu >= 90 {
            result.append(ResourceInsight(resource: .gpu, severity: .warning, title: "GPU capacity is busy",
                detail: "The driver reports \(Format.percent(gpu))% GPU utilization. Reduce concurrent graphics or local model work if it feels slow. Per-app GPU attribution is unavailable."))
        }
        if ["Serious", "Critical"].contains(sample.thermal) {
            result.append(ResourceInsight(resource: .thermal, severity: sample.thermal == "Critical" ? .critical : .warning,
                title: "macOS reports thermal pressure", detail: "Thermal state: \(sample.thermal). Sustained work may be limited by heat. Improve ventilation or reduce concurrent work. This is an OS state, not a temperature measurement."))
        }
        if sample.disk.total > 0, Double(sample.disk.available) / Double(sample.disk.total) < 0.1 {
            result.append(ResourceInsight(resource: .storage, severity: .warning, title: "Startup disk space is low",
                detail: "\(Format.bytes(sample.disk.available)) available, below 10% of capacity. Free space before large builds or downloads."))
        }
        return result.sorted { $0.severity.rawValue > $1.severity.rawValue }
    }
}

/// Alerts require consecutive observations. Pauses, sleep, and large gaps reset duration.
public struct SustainedAlertEngine: Sendable {
    private var since: [String: Double] = [:]
    private var lastSent: [String: Double] = [:]
    private var lastTime: Double?
    public init() {}
    public mutating func resetContinuity() { since = [:]; lastTime = nil }
    public mutating func evaluate(_ insights: [ResourceInsight], uptime: Double, duration: Double = 60,
                                 cooldown: Double = 900, maximumGap: Double = 30) -> [ResourceInsight] {
        if let lastTime, uptime < lastTime || uptime - lastTime > maximumGap { resetContinuity() }
        lastTime = uptime
        let active = insights.filter { $0.severity.rawValue >= ResourceInsight.Severity.warning.rawValue }
        let ids = Set(active.map(\.id))
        since = since.filter { ids.contains($0.key) }
        var alerts: [ResourceInsight] = []
        for insight in active {
            if since[insight.id] == nil { since[insight.id] = uptime }
            if uptime - since[insight.id]! >= duration,
               lastSent[insight.id].map({ uptime - $0 >= cooldown }) ?? true {
                alerts.append(insight); lastSent[insight.id] = uptime
            }
        }
        return alerts
    }
}
