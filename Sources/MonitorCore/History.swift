import Foundation

public struct Contributor: Codable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let footprint: UInt64?
    public let cpu: Double?
    public init(name: String, footprint: UInt64?, cpu: Double?) { self.name = name; self.footprint = footprint; self.cpu = cpu }
}

public struct HistorySample: Identifiable, Sendable, Codable {
    public var id: Date { date }
    public let date: Date
    public let snapshot: SystemSnapshot
    public let contributors: [Contributor]
    public let processesSampledAt: Date?
    public let segment: String
    public init(snapshot: SystemSnapshot, contributors: [Contributor] = [], processesSampledAt: Date? = nil, segment: String = UUID().uuidString) {
        self.date = snapshot.timestamp; self.snapshot = snapshot; self.contributors = Array(contributors.prefix(5))
        self.processesSampledAt = processesSampledAt; self.segment = segment
    }
}

/// Full resolution for 15 minutes; the last observation per 30-second bucket for 24 hours.
public struct HistoryBuffer: Sendable {
    private var recent: [HistorySample] = []
    private var archive: [HistorySample] = []
    private var segment = UUID().uuidString
    public var samples: [HistorySample] { archive + recent }
    public init() {}
    public mutating func breakContinuity() { segment = UUID().uuidString }
    public mutating func append(_ snapshot: SystemSnapshot, contributors: [Contributor] = [], processesSampledAt: Date? = nil) {
        if let last = recent.last ?? archive.last, snapshot.timestamp <= last.date { return }
        if let last = recent.last ?? archive.last, snapshot.timestamp.timeIntervalSince(last.date) > 30 { breakContinuity() }
        recent.append(HistorySample(snapshot: snapshot, contributors: contributors, processesSampledAt: processesSampledAt, segment: segment))
        trim(relativeTo: snapshot.timestamp)
    }
    private mutating func trim(relativeTo date: Date) {
        let cutoff = date.addingTimeInterval(-900)
        let oldCount = recent.prefix(while: { $0.date < cutoff }).count
        for sample in recent.prefix(oldCount) {
            if let last = archive.last, Int(last.date.timeIntervalSince1970 / 30) == Int(sample.date.timeIntervalSince1970 / 30), last.segment == sample.segment {
                archive[archive.count - 1] = sample
            } else { archive.append(sample) }
        }
        recent.removeFirst(oldCount)
        archive.removeAll { $0.date < date.addingTimeInterval(-86400) }
        // Defensive bounds for imported data or clocks that run unusually quickly.
        if recent.count > 901 { recent.removeFirst(recent.count - 901) }
        if archive.count > 3000 { archive.removeFirst(archive.count - 3000) }
    }
    public mutating func restore(_ samples: [HistorySample], now: Date = Date()) {
        self = Self()
        // Retain recorded segment boundaries. Ordinary archive buckets can be
        // 31 seconds apart due to scheduling and must not create new gaps.
        let unique = Dictionary(samples.map { ($0.date, $0) }, uniquingKeysWith: { _, latest in latest })
        recent = unique.values.filter { $0.date > now.addingTimeInterval(-86400) && $0.date <= now }.sorted { $0.date < $1.date }
        trim(relativeTo: now)
        breakContinuity()
    }
    /// Bound chart work while retaining endpoints and explicit segment boundaries.
    public static func chartSamples(_ samples: [HistorySample], limit: Int = 240) -> [HistorySample] {
        guard limit >= 2, samples.count > limit else { return samples }
        let step = Double(samples.count - 1) / Double(limit - 1)
        return (0..<limit).map { samples[Int((Double($0) * step).rounded())] }
    }
}

public actor HistoryDisk {
    private struct Envelope: Codable { let version: Int; let samples: [HistorySample] }
    private let url: URL
    public init(url: URL) { self.url = url }
    public func load(now: Date = Date()) throws -> [HistorySample] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 8_388_608 else { throw CocoaError(.fileReadTooLarge) }
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url))
        guard envelope.version == 2, envelope.samples.count <= 4000 else { throw CocoaError(.fileReadCorruptFile) }
        return envelope.samples.filter { $0.date > now.addingTimeInterval(-86400) && $0.date <= now }
    }
    public func save(_ samples: [HistorySample]) throws {
        guard !Task.isCancelled else { return }
        let data = try JSONEncoder().encode(Envelope(version: 2, samples: Array(samples.suffix(4000))))
        guard data.count <= 8_388_608 else { throw CocoaError(.fileWriteOutOfSpace) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public func clear() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
