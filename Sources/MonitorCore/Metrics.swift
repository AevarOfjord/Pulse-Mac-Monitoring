import Foundation

public struct CPUTicks: Sendable, Equatable {
    public let user: UInt32
    public let system: UInt32
    public let idle: UInt32
    public let nice: UInt32
    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32 = 0) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }
    public func utilization(since old: CPUTicks) -> (total: Double, user: Double, system: Double) {
        let u = Double(user &- old.user) + Double(nice &- old.nice)
        let s = Double(system &- old.system)
        let i = Double(idle &- old.idle)
        let sum = u + s + i
        guard sum > 0 else { return (0, 0, 0) }
        return ((u + s) / sum * 100, u / sum * 100, s / sum * 100)
    }
}

public struct CounterPair: Sendable {
    public var incoming: UInt64
    public var outgoing: UInt64
    public init(_ incoming: UInt64 = 0, _ outgoing: UInt64 = 0) {
        self.incoming = incoming; self.outgoing = outgoing
    }
    public func rate(since old: CounterPair?, elapsed: Double) -> CounterRate? {
        guard let old, elapsed > 0, incoming >= old.incoming, outgoing >= old.outgoing else { return nil }
        return CounterRate(incoming: Double(incoming - old.incoming) / elapsed,
                           outgoing: Double(outgoing - old.outgoing) / elapsed)
    }
}

public struct CounterRate: Sendable, Codable {
    public var incoming: Double = 0
    public var outgoing: Double = 0
    public init(incoming: Double = 0, outgoing: Double = 0) {
        self.incoming = incoming; self.outgoing = outgoing
    }
}

public struct MemoryMetrics: Sendable, Codable {
    public var total: UInt64 = 0
    public var app: UInt64 = 0
    public var wired: UInt64 = 0
    public var compressed: UInt64 = 0
    public var cached: UInt64 = 0
    public var swapUsed: UInt64?
    public var swapActivity: CounterRate?
    public var pressure: String = "Unavailable"
    public var used: UInt64 { min(total, app + wired + compressed) }
    public var available: UInt64 { total > used ? total - used : 0 }
    public var percent: Double { total > 0 ? Double(used) / Double(total) * 100 : 0 }
    public init() {}
}

public struct GPUMetrics: Sendable, Codable {
    public var name: String = "Graphics processor"
    public var utilization: Double?
    public var renderer: Double?
    public var tiler: Double?
    public var memoryUsed: UInt64?
    public var cores: Int?
    public init() {}
}

public struct DiskMetrics: Sendable, Codable {
    public var total: UInt64 = 0
    public var available: UInt64 = 0
    public var activity: CounterRate?
    public var used: UInt64 { total > available ? total - available : 0 }
    public var percent: Double { total > 0 ? Double(used) / Double(total) * 100 : 0 }
    public init() {}
}

public struct NetworkInterface: Sendable, Codable, Identifiable {
    public var id: String { name }
    public let name: String
    public let rate: CounterRate?
    public let received: UInt64
    public let sent: UInt64
}

public struct ProcessMetric: Sendable, Identifiable, Codable {
    public var id: String { "\(pid):\(birthID)" }
    public let pid: Int
    public let parentPID: Int
    public let birthID: UInt64
    public let name: String
    public let path: String
    public let cpu: Double?
    public let residentMemory: UInt64?
    public let footprint: UInt64?
    public let compressedMemory: UInt64?
    public let peakFootprint: UInt64?
    public let workload: WorkloadMetadata?
    public var startedAt: Date { Date(timeIntervalSince1970: Double(birthID) / 1_000_000) }
    public var memory: UInt64 { footprint ?? residentMemory ?? 0 }
    public var appBundle: String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }
    public init(pid: Int, parentPID: Int = 1, birthID: UInt64 = 1, name: String,
                path: String = "", cpu: Double? = nil, residentMemory: UInt64? = nil,
                footprint: UInt64? = nil, compressedMemory: UInt64? = nil,
                peakFootprint: UInt64? = nil, workload: WorkloadMetadata? = nil) {
        self.pid = pid; self.parentPID = parentPID; self.birthID = birthID
        self.name = name; self.path = path; self.cpu = cpu; self.residentMemory = residentMemory
        self.footprint = footprint; self.compressedMemory = compressedMemory
        self.peakFootprint = peakFootprint; self.workload = workload
    }
}

public struct ProcessCPUCounters: Sendable {
    public let birthID: UInt64
    public let nanoseconds: UInt64
    public let uptime: Double
    public init(birthID: UInt64, nanoseconds: UInt64, uptime: Double) {
        self.birthID = birthID; self.nanoseconds = nanoseconds; self.uptime = uptime
    }
    public func percent(since old: Self?) -> Double? {
        guard let old, old.birthID == birthID, uptime > old.uptime, nanoseconds >= old.nanoseconds else { return nil }
        return Double(nanoseconds - old.nanoseconds) / 1_000_000_000 / (uptime - old.uptime) * 100
    }
}

public struct ProcessBatch: Sendable {
    public var processes: [ProcessMetric]
    public var unavailableCount: Int
    public var durationMilliseconds: Double
    public var sampledAt: Date
    public init(processes: [ProcessMetric] = [], unavailableCount: Int = 0,
                durationMilliseconds: Double = 0, sampledAt: Date = Date()) {
        self.processes = processes; self.unavailableCount = unavailableCount
        self.durationMilliseconds = durationMilliseconds; self.sampledAt = sampledAt
    }
}

public struct SystemSnapshot: Sendable, Codable {
    public var timestamp = Date()
    public var cpu: Double?
    public var cpuUser: Double = 0
    public var cpuSystem: Double = 0
    public var cores: [Double] = []
    public var memory: MemoryMetrics?
    public var gpu = GPUMetrics()
    public var disk = DiskMetrics()
    public var network: CounterRate?
    public var interfaces: [NetworkInterface] = []
    public var thermal = "Unavailable"
    public var temperatures: TemperatureSummary?
    public var uptime: Double = 0
    public var loadAverage: [Double] = []
    public var errors: [String] = []
    public init() {}
}

public enum Format {
    public static func temperature(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.1f °C", value)
    }
    public static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .binary)
    }
    public static func rate(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        if value < 1024 { return String(format: "%.0f B/s", value) }
        if value < 1_048_576 { return String(format: "%.1f KB/s", value / 1024) }
        return String(format: "%.1f MB/s", value / 1_048_576)
    }
    public static func percent(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? "—"
    }
    public static func uptime(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        return days > 0 ? "\(days)d \(hours)h" : "\(hours)h \(minutes)m"
    }
}
