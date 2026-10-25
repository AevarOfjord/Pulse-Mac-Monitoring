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
    public var id: Int { pid }
    public let pid: Int
    public let name: String
    public let path: String
    public let cpu: Double
    public let memory: UInt64
    public static func parse(_ line: Substring) -> ProcessMetric? {
        let fields = line.split(maxSplits: 3, omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
        guard fields.count == 4, let pid = Int(fields[0]), let cpu = Double(fields[1]),
              let rss = UInt64(fields[2]) else { return nil }
        let path = String(fields[3])
        return ProcessMetric(pid: pid, name: URL(fileURLWithPath: path).lastPathComponent,
                             path: path, cpu: cpu, memory: rss * 1024)
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
    public var uptime: Double = 0
    public var loadAverage: [Double] = []
    public var errors: [String] = []
    public init() {}
}

public enum Format {
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
