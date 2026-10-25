import Foundation
import MonitorCore
import ProcessSupport
import Darwin

@main struct Diagnostics {
    static func main() async throws {
        let sampler = SystemSampler()
        if CommandLine.arguments.contains("--temperatures") {
            var previous: Date?; var refreshes = 0
            for index in 0...6 {
                _ = await sampler.sample()
                let report = await sampler.temperatureReport()
                if report.sampledAt != previous {
                    previous = report.sampledAt; refreshes += 1
                    print("Temperature read: \(report.readings.count)/\(report.discoveredCount) valid sensors; \(report.rejectedCount) omitted; \(String(format: "%.2f", report.durationMilliseconds)) ms")
                    for group in [TemperatureGroup.pmu, .battery, .storage] {
                        print("\(group.title) max: \(Format.temperature(report.summary?.maximum(for: group)))")
                    }
                }
                if CommandLine.arguments.contains("--require-temperatures"), report.readings.isEmpty { fatalError("No valid native temperatures") }
                if index < 6 { try await Task.sleep(for: .seconds(1)) }
            }
            guard refreshes == 2 else { fatalError("Temperature cache refresh count mismatch: \(refreshes)") }
            print("Temperature cadence verified: two native reads across seven system samples")
            return
        }
        _ = await sampler.sample()
        _ = await sampler.processes()
        try await Task.sleep(for: .seconds(1))
        let snapshot = await sampler.sample()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if !CommandLine.arguments.contains("--smoke") { print(String(decoding: try encoder.encode(snapshot), as: UTF8.self)) }
        let batch = await sampler.processes()
        let processes = batch.processes
        print("\nProcesses: \(processes.count)")
        if CommandLine.arguments.contains("--smoke") {
            // Compare interval deltas: cumulative lifetime baselines can differ
            // between the task and BSD APIs after process launch/exec.
            var beforeNative = PulseProcessInfo(); var beforeUsage = rusage()
            guard pulse_read_process(getpid(), &beforeNative) != 0, beforeNative.has_cpu != 0,
                  getrusage(RUSAGE_SELF, &beforeUsage) == 0 else { fatalError("Self resource access failed") }
            func cpuSeconds(_ usage: rusage) -> Double {
                Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
            }
            let deadline = ProcessInfo.processInfo.systemUptime + 0.3
            var iterations: UInt64 = 0
            while ProcessInfo.processInfo.systemUptime < deadline { iterations &+= 1 }
            var native = PulseProcessInfo(); var usage = rusage()
            guard pulse_read_process(getpid(), &native) != 0, native.has_cpu != 0, getrusage(RUSAGE_SELF, &usage) == 0 else { fatalError("Self resource access failed") }
            guard native.cpu_nanoseconds >= beforeNative.cpu_nanoseconds else { fatalError("Process CPU counter decreased") }
            let seconds = cpuSeconds(usage) - cpuSeconds(beforeUsage)
            let nativeSeconds = Double(native.cpu_nanoseconds - beforeNative.cpu_nanoseconds) / 1_000_000_000
            guard abs(nativeSeconds - seconds) < max(0.005, seconds * 0.15) else {
                fatalError("Process CPU clock delta mismatch: task=\(nativeSeconds)s, getrusage=\(seconds)s; totals task=\(native.cpu_nanoseconds)ns, BSD=\(cpuSeconds(usage))s")
            }
            guard snapshot.cpu.map({ $0.isFinite && (0...100).contains($0) }) == true,
                  snapshot.memory?.total ?? 0 > 0,
                  let own = processes.first(where: { $0.pid == Int(ProcessInfo.processInfo.processIdentifier) }),
                  own.footprint != nil, own.cpu != nil else { fatalError("Native sampler smoke check failed") }
            print("Native sampler smoke check passed; scan \(batch.durationMilliseconds) ms; CPU clock verified (\(iterations) iterations)")
            return
        }
        for process in processes.prefix(5) {
            print("\(process.pid) \(process.name) \(Format.percent(process.cpu))% \(Format.bytes(process.memory))")
        }
    }
}
