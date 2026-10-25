import Foundation
import Testing
@testable import MonitorCore

struct VersionTwoTests {
    @Test func footprintAndResidentAreDistinctAndUnknownStaysUnknown() {
        let p = ProcessMetric(pid: 2, name: "job", residentMemory: 100, footprint: 900)
        #expect(p.memory == 900)
        #expect(p.compressedMemory == nil)
        #expect(ProcessMetric(pid: 2, birthID: 1, name: "old").id != ProcessMetric(pid: 2, birthID: 2, name: "new").id)
        #expect(ProcessMetric(pid: 3, name: "restricted").footprint == nil)
    }
    @Test func appPathsWithSpacesAndHelpersAreGrouped() {
        let app = ProcessMetric(pid: 2, name: "Great App", path: "/Applications/Great App.app/Contents/MacOS/Great App", footprint: 200)
        let helper = ProcessMetric(pid: 3, parentPID: 2, name: "helper", footprint: 100)
        let groups = ProcessGrouping.groups([helper, app])
        #expect(groups.count == 1)
        #expect(groups.first?.name == "Great App")
        #expect(groups.first?.footprint == 300)
        #expect(groups.first?.members.count == 2)
    }
    @Test func concurrentJobsStaySeparateAndOwnDescendants() {
        let job = WorkloadMetadata(command: "test", project: "Example")
        let processes = [ProcessMetric(pid: 2, name: "dotnet", footprint: 10, workload: job),
                         ProcessMetric(pid: 3, parentPID: 2, name: "testhost", footprint: 900),
                         ProcessMetric(pid: 4, name: "dotnet", footprint: 20, workload: job),
                         ProcessMetric(pid: 5, parentPID: 4, name: "testhost", footprint: 500)]
        let groups = ProcessGrouping.groups(processes)
        #expect(groups.count == 2)
        #expect(groups[0].footprint == 910)
        #expect(groups[1].footprint == 520)
        #expect(Set(groups.flatMap(\.members).map(\.id)).count == 4)
    }
    @Test func cyclesPIDReuseAndPartialCountersAreHandled() {
        let a = ProcessMetric(pid: 2, parentPID: 3, birthID: 20, name: "a", workload: WorkloadMetadata(command: "test"))
        let b = ProcessMetric(pid: 3, parentPID: 2, birthID: 10, name: "b", footprint: 100)
        let groups = ProcessGrouping.groups([a, b])
        #expect(groups.flatMap(\.members).count == 2)
        #expect(groups.first(where: { $0.root.pid == 2 })?.footprintIsPartial == true)
        #expect(groups.first(where: { $0.root.pid == 3 })?.kind == .process)
    }
    @Test func argumentDecoderStopsBeforeEnvironmentAndSanitizesMetadata() {
        let args = ["dotnet", "test", "/private/project/Example.csproj", "--secret", "sensitive"]
        var count = Int32(args.count)
        var data = Data(bytes: &count, count: 4)
        data.append(Data("/opt/dotnet\0\0\0".utf8))
        data.append(Data((args.joined(separator: "\0") + "\0TOKEN=environment-secret\0").utf8))
        let decoded = WorkloadMetadata.decodeArguments(data)
        #expect(decoded == args)
        let metadata = WorkloadMetadata.inspect(arguments: decoded)
        #expect(metadata == WorkloadMetadata(command: "test", project: "Example"))
        let encoded = String(decoding: try! JSONEncoder().encode(metadata), as: UTF8.self)
        #expect(!encoded.contains("private"))
        #expect(!encoded.contains("sensitive"))
        #expect(!encoded.contains("TOKEN"))
        #expect(WorkloadMetadata.decodeArguments(Data([1, 0])) == [])
        #expect(WorkloadMetadata.inspect(arguments: ["dotnet", "--password"]) == nil)
    }
    @Test func highMemoryPercentageOrOldSwapAloneDoesNotTriggerPressure() {
        var s = SystemSnapshot(); var m = MemoryMetrics()
        m.total = 1000; m.app = 950; m.pressure = "Normal"; m.swapUsed = 20_000_000_000; s.memory = m
        #expect(InsightAnalyzer.analyze(s, groups: []).isEmpty)
        m.pressure = "Critical"; s.memory = m
        #expect(InsightAnalyzer.analyze(s, groups: []).first?.severity == .critical)
        m.pressure = "Normal"; m.swapActivity = CounterRate(incoming: 30 * 1_048_576); s.memory = m
        #expect(InsightAnalyzer.analyze(s, groups: []).first?.resource == .memory)
    }
    @Test func independentResourceSignalsAreExplained() {
        var s = SystemSnapshot(); s.cpu = 95; s.gpu.utilization = 99; s.thermal = "Serious"; s.disk.total = 100; s.disk.available = 9
        #expect(Set(InsightAnalyzer.analyze(s, groups: []).map(\.id)) == ["cpu", "gpu", "thermal", "storage"])
    }
    private var warning: ResourceInsight { ResourceInsight(resource: .memory, severity: .warning, title: "Pressure", detail: "Observed") }
    @Test func alertsRequireDurationRespectCooldownAndRecover() {
        var engine = SustainedAlertEngine()
        #expect(engine.evaluate([warning], uptime: 0, duration: 60).isEmpty)
        #expect(engine.evaluate([warning], uptime: 30, duration: 60).isEmpty)
        #expect(engine.evaluate([warning], uptime: 60, duration: 60).count == 1)
        #expect(engine.evaluate([warning], uptime: 61, duration: 60).isEmpty)
        #expect(engine.evaluate([], uptime: 62).isEmpty)
        for t in stride(from: 900.0, through: 960, by: 30) { _ = engine.evaluate([warning], uptime: t, duration: 60) }
        #expect(engine.evaluate([warning], uptime: 961, duration: 60).isEmpty) // Sent at 960.
    }
    @Test func alertGapsSleepAndPausesDoNotCountAsSustained() {
        var engine = SustainedAlertEngine()
        _ = engine.evaluate([warning], uptime: 0, duration: 30)
        #expect(engine.evaluate([warning], uptime: 1000, duration: 30).isEmpty)
        engine.resetContinuity()
        #expect(engine.evaluate([warning], uptime: 1010, duration: 30).isEmpty)
        #expect(engine.evaluate([warning], uptime: 1040, duration: 30).count == 1)
    }
    @Test func historyRetains24HoursAndBoundsCharts() {
        var buffer = HistoryBuffer()
        let start = Date(timeIntervalSince1970: 1_000_000)
        for index in 0...90_000 {
            var s = SystemSnapshot(); s.timestamp = start.addingTimeInterval(Double(index)); s.cpu = Double(index % 100)
            buffer.append(s)
        }
        let samples = buffer.samples
        #expect(samples.count <= 3901)
        #expect(samples.first!.date >= start.addingTimeInterval(90_000 - 86400))
        #expect(samples.last!.date == start.addingTimeInterval(90_000))
        #expect(samples.suffix(901).count == 901)
        let chart = HistoryBuffer.chartSamples(samples)
        #expect(chart.count == 240)
        #expect(chart.first?.date == samples.first?.date)
        #expect(chart.last?.date == samples.last?.date)
    }
    @Test func historyGapsAndExplicitPausesBreakLines() {
        var buffer = HistoryBuffer(); var s = SystemSnapshot()
        s.timestamp = Date(timeIntervalSince1970: 1000); buffer.append(s)
        s.timestamp = s.timestamp.addingTimeInterval(2); buffer.append(s)
        #expect(buffer.samples[0].segment == buffer.samples[1].segment)
        buffer.breakContinuity(); s.timestamp = s.timestamp.addingTimeInterval(2); buffer.append(s)
        s.timestamp = s.timestamp.addingTimeInterval(100); buffer.append(s)
        #expect(buffer.samples[1].segment != buffer.samples[2].segment)
        #expect(buffer.samples[2].segment != buffer.samples[3].segment)
    }
    @Test func restoredHistoryPreservesSegmentsAndMergesSessionData() {
        let now = Date()
        var a = SystemSnapshot(); a.timestamp = now.addingTimeInterval(-1000)
        var b = a; b.timestamp = a.timestamp.addingTimeInterval(31)
        var c = b; c.timestamp = now.addingTimeInterval(-1)
        let saved = [HistorySample(snapshot: a, segment: "archive"), HistorySample(snapshot: b, segment: "archive")]
        let session = HistorySample(snapshot: c, segment: "session")
        var buffer = HistoryBuffer(); buffer.restore(saved + [session, session], now: now)
        #expect(buffer.samples.count == 3)
        #expect(buffer.samples[0].segment == "archive")
        #expect(buffer.samples[1].segment == "archive")
        #expect(buffer.samples[2].segment == "session")
    }
    @Test func localHistoryRoundTripsWithoutPathsAndCanBeDeleted() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("history.json"); let disk = HistoryDisk(url: url)
        let sample = HistorySample(snapshot: SystemSnapshot(), contributors: [Contributor(name: "Example", footprint: 100, cpu: nil)])
        try await disk.save([sample])
        let loaded = try await disk.load(now: Date().addingTimeInterval(1))
        #expect(loaded.count == 1)
        #expect(loaded.first?.contributors.first?.name == "Example")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.contains("path")); #expect(!text.contains("arguments"))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try await disk.clear()
        #expect(try await disk.load().isEmpty)
    }
    @Test func oversizedHistoryIsRejectedBeforeDecoding() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 0, count: 8_388_609).write(to: url)
        await #expect(throws: (any Error).self) { try await HistoryDisk(url: url).load() }
    }
}
