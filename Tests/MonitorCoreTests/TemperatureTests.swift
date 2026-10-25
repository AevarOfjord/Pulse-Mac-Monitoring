import Foundation
import Testing
@testable import MonitorCore

struct TemperatureTests {
    private func candidate(_ id: String, _ value: Double?, _ name: String = "PMU tdie1") -> TemperatureCandidate {
        TemperatureCandidate(id: id, name: name, celsius: value)
    }

    @Test func invalidThermalEventsAreExcludedAndUnknownNamesStayUnknown() {
        let report = TemperatureReport(candidates: [candidate("a", 72), candidate("b", -9199), candidate("c", nil),
            candidate("d", .nan), candidate("e", .infinity), candidate("f", 151), candidate("g", -21),
            candidate("h", 49, "CPU mystery sensor"), candidate("i", 32, "gas gauge battery"), candidate("j", 44, "NAND CH0 temp")],
            sampledAt: Date(), availability: .available)
        #expect(report.readings.count == 4)
        #expect(report.rejectedCount == 6)
        #expect(report.readings.first(where: { $0.id == "h" })?.group == .other)
        #expect(report.summary?.pmuMaximum == 72)
        #expect(report.summary?.batteryMaximum == 32)
        #expect(report.summary?.storageMaximum == 44)
        #expect(TemperatureReport(availability: .available).availability == .unavailable)
    }

    @Test func distinctSensorsWithRepeatedNamesAreRetainedAndMaximaAreUsed() {
        let report = TemperatureReport(candidates: [candidate("a", 60), candidate("b", 75), candidate("a", 60),
            candidate("c", 50, " \nNAND CH0 temp\u{0} ")], discoveredCount: 5, sampledAt: Date())
        #expect(report.readings.count == 3)
        #expect(report.readings.filter { $0.name == "PMU tdie1" }.count == 2)
        #expect(report.summary?.pmuMaximum == 75)
        #expect(report.summary?.storageMaximum == 50)
        #expect(report.summary?.batteryMaximum == nil)
        #expect(report.rejectedCount == 2)
        #expect(TemperatureReading(candidate("empty", 1, "\n"))?.name == "Thermal sensor")
        #expect(TemperatureReading(candidate("long", 1, String(repeating: "x", count: 300)))?.name.count == 96)
    }

    @Test func temperaturesCacheForFiveSecondsAndResetAfterWake() {
        var reads = 0; var resets = 0
        let reader = TemperatureReader(read: { uptime in
            reads += 1
            return TemperatureReport(candidates: [candidate("a", uptime)], sampledAt: Date(timeIntervalSince1970: uptime))
        }, invalidate: { resets += 1 })
        #expect(reader.sample(uptime: 10).summary?.pmuMaximum == 10)
        #expect(reader.sample(uptime: 14.99).summary?.pmuMaximum == 10)
        #expect(reads == 1)
        #expect(reader.sample(uptime: 15).summary?.pmuMaximum == 15)
        #expect(reader.sample(uptime: 2).summary?.pmuMaximum == 2)
        reader.reset()
        #expect(reader.report.availability == .notSampled)
        _ = reader.sample(uptime: 2.1)
        #expect(reads == 4)
        #expect(resets == 1)
    }

    @Test func missingEventsClearOldTemperaturesAndUnavailableFormatsAsDash() {
        var reads = 0
        let reader = TemperatureReader(read: { _ in
            reads += 1
            return TemperatureReport(candidates: reads == 1 ? [candidate("a", 65)] : [], sampledAt: Date(), availability: .unavailable)
        })
        #expect(reader.sample(uptime: 1).summary?.pmuMaximum == 65)
        #expect(reader.sample(uptime: 6).summary == nil)
        #expect(Format.temperature(nil) == "—")
        #expect(Format.temperature(.nan) == "—")
        #expect(Format.temperature(.infinity) == "—")
        #expect(Format.temperature(32.25) == "32.2 °C")
    }

    @Test func oldSnapshotsDecodeAndNewHistoryStoresOnlyCompactSummary() async throws {
        let encoder = JSONEncoder(); let decoder = JSONDecoder()
        let old = try encoder.encode(SystemSnapshot())
        #expect(!String(decoding: old, as: UTF8.self).contains("temperatures"))
        #expect(try decoder.decode(SystemSnapshot.self, from: old).temperatures == nil)
        let report = TemperatureReport(candidates: [candidate("private-registry-id", 70, "PMU tdie-private-name")], sampledAt: Date())
        var snapshot = SystemSnapshot(); snapshot.temperatures = report.summary
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("history.json"); let disk = HistoryDisk(url: url)
        try await disk.save([HistorySample(snapshot: snapshot)])
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.contains("private-registry-id"))
        #expect(!text.contains("PMU tdie-private-name"))
        let loaded = try await disk.load(now: Date().addingTimeInterval(1))
        #expect(loaded.first?.snapshot.temperatures?.pmuMaximum == 70)
        #expect(loaded.first?.snapshot.temperatures?.sampledAt == report.sampledAt)
        #expect(try encoder.encode(snapshot).count - old.count < 200)
    }
}
