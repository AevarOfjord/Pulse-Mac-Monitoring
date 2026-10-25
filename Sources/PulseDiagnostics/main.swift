import Foundation
import MonitorCore

@main struct Diagnostics {
    static func main() async throws {
        let sampler = SystemSampler()
        _ = await sampler.sample()
        try await Task.sleep(for: .seconds(1))
        let snapshot = await sampler.sample()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        print(String(decoding: try encoder.encode(snapshot), as: UTF8.self))
        let processes = await sampler.processes()
        print("\nProcesses: \(processes.count)")
        for process in processes.prefix(5) {
            print("\(process.pid) \(process.name) \(Format.percent(process.cpu))% \(Format.bytes(process.memory))")
        }
    }
}
