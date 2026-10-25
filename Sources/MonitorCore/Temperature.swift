import Foundation
import ProcessSupport

public enum TemperatureGroup: String, CaseIterable, Sendable {
    case pmu, battery, storage, other
    public var title: String {
        switch self {
        case .pmu: return "PMU die"
        case .battery: return "Battery"
        case .storage: return "Storage"
        case .other: return "Other sensors"
        }
    }
    public static func classify(_ name: String) -> Self {
        let name = name.lowercased()
        if name.hasPrefix("pmu tdie") { return .pmu }
        if name.contains("battery") { return .battery }
        if name.contains("nand") { return .storage }
        return .other
    }
}

public struct TemperatureCandidate: Sendable {
    public let id: String
    public let name: String
    public let celsius: Double?
    public init(id: String, name: String, celsius: Double?) {
        self.id = id; self.name = name; self.celsius = celsius
    }
}

public struct TemperatureReading: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let celsius: Double
    public var group: TemperatureGroup { TemperatureGroup.classify(name) }
    public init?(_ candidate: TemperatureCandidate) {
        // A broad plausibility filter, not a thermal warning threshold.
        guard let value = candidate.celsius, value.isFinite, (-20...150).contains(value) else { return nil }
        id = candidate.id
        let clean = candidate.name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let name = String(String.UnicodeScalarView(clean)).trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = name.isEmpty ? "Thermal sensor" : String(name.prefix(96))
        celsius = value
    }
}

/// Only these compact maxima enter history and exported system snapshots.
public struct TemperatureSummary: Sendable, Codable {
    public var sampledAt: Date
    public var pmuMaximum: Double?
    public var batteryMaximum: Double?
    public var storageMaximum: Double?
    public init(sampledAt: Date, pmuMaximum: Double? = nil, batteryMaximum: Double? = nil, storageMaximum: Double? = nil) {
        self.sampledAt = sampledAt; self.pmuMaximum = pmuMaximum
        self.batteryMaximum = batteryMaximum; self.storageMaximum = storageMaximum
    }
    public func maximum(for group: TemperatureGroup) -> Double? {
        switch group {
        case .pmu: return pmuMaximum
        case .battery: return batteryMaximum
        case .storage: return storageMaximum
        case .other: return nil
        }
    }
}

public enum TemperatureAvailability: Sendable {
    case notSampled, available, unavailable, unsupported
}

public struct TemperatureReport: Sendable {
    public let sampledAt: Date?
    public let readings: [TemperatureReading]
    public let discoveredCount: Int
    public let rejectedCount: Int
    public let availability: TemperatureAvailability
    public let durationMilliseconds: Double
    public var summary: TemperatureSummary? {
        guard let sampledAt, !readings.isEmpty else { return nil }
        func maximum(_ group: TemperatureGroup) -> Double? { readings.filter { $0.group == group }.map(\.celsius).max() }
        return TemperatureSummary(sampledAt: sampledAt, pmuMaximum: maximum(.pmu), batteryMaximum: maximum(.battery), storageMaximum: maximum(.storage))
    }
    public init(candidates: [TemperatureCandidate] = [], discoveredCount: Int = 0, sampledAt: Date? = nil,
                availability: TemperatureAvailability = .notSampled, durationMilliseconds: Double = 0) {
        var ids = Set<String>()
        readings = candidates.compactMap(TemperatureReading.init).filter { ids.insert($0.id).inserted }
            .sorted { $0.name == $1.name ? $0.id < $1.id : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.discoveredCount = max(discoveredCount, candidates.count)
        rejectedCount = max(0, self.discoveredCount - readings.count)
        self.sampledAt = sampledAt
        self.availability = readings.isEmpty ? (availability == .available ? .unavailable : availability) : .available
        self.durationMilliseconds = durationMilliseconds
    }
}

/// Owned by SystemSampler; both the cache and the native client stay on its actor.
final class TemperatureReader {
    private let read: (Double) -> TemperatureReport
    private let invalidate: () -> Void
    private var lastUptime: Double?
    private(set) var report = TemperatureReport()
    init() {
        let source = NativeTemperatureSource()
        read = { source.read(uptime: $0) }; invalidate = { source.reset() }
    }
    init(read: @escaping (Double) -> TemperatureReport, invalidate: @escaping () -> Void = {}) {
        self.read = read; self.invalidate = invalidate
    }
    func sample(uptime: Double) -> TemperatureReport {
        if let lastUptime, uptime >= lastUptime, uptime - lastUptime < 5 { return report }
        report = read(uptime); lastUptime = uptime
        return report
    }
    func reset() { lastUptime = nil; report = TemperatureReport(); invalidate() }
}

private final class NativeTemperatureSource {
    private let reader = pulse_temperature_create()
    deinit { pulse_temperature_destroy(reader) }
    func reset() { pulse_temperature_reset(reader) }
    func read(uptime: Double) -> TemperatureReport {
        let started = ProcessInfo.processInfo.systemUptime
        var sensors = [PulseTemperatureSensor](repeating: PulseTemperatureSensor(), count: 256)
        var discovered: UInt32 = 0
        let count = pulse_temperature_read(reader, &sensors, Int32(sensors.count), &discovered, uptime)
        let candidates = sensors.prefix(max(0, Int(count))).map { sensor in
            var name = sensor.name
            let label = withUnsafePointer(to: &name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: 128) { String(cString: $0) }
            }
            return TemperatureCandidate(id: String(sensor.registry_id), name: label, celsius: sensor.has_value != 0 ? sensor.celsius : nil)
        }
        return TemperatureReport(candidates: candidates, discoveredCount: Int(discovered), sampledAt: Date(),
                                 availability: count == -2 ? .unsupported : .unavailable,
                                 durationMilliseconds: (ProcessInfo.processInfo.systemUptime - started) * 1000)
    }
}
