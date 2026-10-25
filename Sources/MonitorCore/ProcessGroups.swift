import Foundation

/// Only the command category and project basename survive argument inspection.
/// Full arguments, environment variables, and working-directory paths are discarded.
public struct WorkloadMetadata: Codable, Sendable, Equatable {
    public let command: String
    public let project: String?
    public init(command: String, project: String? = nil) { self.command = command; self.project = project }
    public static func inspect(arguments: [String]) -> Self? {
        guard arguments.count > 1 else { return nil }
        let allowed = Set(["test", "build", "run", "watch", "publish", "restore"])
        guard allowed.contains(arguments[1]) else { return nil }
        let extensions = Set(["csproj", "sln", "slnx", "xcodeproj", "xcworkspace"])
        let project = arguments.dropFirst(2).first { !$0.hasPrefix("-") && !$0.contains("=") && extensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
            .map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
        return Self(command: arguments[1], project: project)
    }
    public static func decodeArguments(_ data: Data) -> [String] {
        guard data.count > 4 else { return [] }
        let count = data.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        guard count > 0, count <= 4096 else { return [] }
        let bytes = [UInt8](data)
        var cursor = 4
        while cursor < bytes.count && bytes[cursor] != 0 { cursor += 1 }
        while cursor < bytes.count && bytes[cursor] == 0 { cursor += 1 }
        var result: [String] = []
        for _ in 0..<count {
            guard cursor < bytes.count else { return [] }
            let start = cursor
            while cursor < bytes.count && bytes[cursor] != 0 { cursor += 1 }
            guard cursor < bytes.count else { return [] }
            result.append(String(decoding: bytes[start..<cursor], as: UTF8.self))
            cursor += 1
        }
        return result
    }
}

public struct ProcessGroup: Identifiable, Sendable {
    public enum Kind: String, Sendable { case workload, app, process }
    public let id: String
    public let name: String
    public let kind: Kind
    public let root: ProcessMetric
    public let members: [ProcessMetric]
    public var footprint: UInt64? {
        let values = members.compactMap(\.footprint)
        return values.isEmpty ? nil : values.reduce(0, +)
    }
    public var footprintIsPartial: Bool { members.contains { $0.footprint == nil } }
    public var cpu: Double? {
        let values = members.compactMap(\.cpu)
        return values.isEmpty ? nil : values.reduce(0, +)
    }
    public var residentMemory: UInt64? {
        let values = members.compactMap(\.residentMemory)
        return values.isEmpty ? nil : values.reduce(0, +)
    }
}

public enum ProcessGrouping {
    public static func groups(_ processes: [ProcessMetric]) -> [ProcessGroup] {
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var buckets: [String: (String, ProcessGroup.Kind, ProcessMetric, [ProcessMetric])] = [:]
        for process in processes {
            var chain = [process]
            var visited: Set<Int> = [process.pid]
            var current = process
            while let parent = byPID[current.parentPID], parent.pid > 1,
                  parent.birthID <= current.birthID, visited.insert(parent.pid).inserted, chain.count < 64 {
                chain.append(parent); current = parent
            }
            let key: String
            let title: String
            let kind: ProcessGroup.Kind
            let root: ProcessMetric
            if let job = chain.first(where: { $0.workload != nil }), let metadata = job.workload {
                key = "job:\(job.id)"; kind = .workload; root = job
                title = "\(job.name) \(metadata.command)" + (metadata.project.map { " · \($0)" } ?? "")
            } else if let app = chain.first(where: { $0.appBundle != nil }), let bundle = app.appBundle {
                key = "app:\(bundle)"; kind = .app; root = chain.last(where: { $0.appBundle == bundle }) ?? app
                title = URL(fileURLWithPath: bundle).deletingPathExtension().lastPathComponent
            } else {
                key = "process:\(process.id)"; kind = .process; root = process; title = process.name
            }
            if buckets[key] == nil { buckets[key] = (title, kind, root, []) }
            else if kind == .app, root.birthID < buckets[key]!.2.birthID { buckets[key]!.2 = root }
            buckets[key]!.3.append(process)
        }
        return buckets.map { key, entry in
            ProcessGroup(id: key, name: entry.0, kind: entry.1, root: entry.2,
                         members: entry.3.sorted { $0.memory > $1.memory })
        }.sorted { ($0.footprint ?? 0) > ($1.footprint ?? 0) }
    }
}
