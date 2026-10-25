import Testing
@testable import MonitorCore

struct MetricsTests {
    @Test func cpuUsesIntervalDeltasAndIncludesNice() {
        let old = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let new = CPUTicks(user: 120, system: 60, idle: 915, nice: 5)
        let result = new.utilization(since: old)
        #expect(abs(result.total - 35) < 0.001)
        #expect(abs(result.user - 25) < 0.001)
        #expect(abs(result.system - 10) < 0.001)
    }
    @Test func cpuTickWraparound() {
        let old = CPUTicks(user: UInt32.max - 9, system: 0, idle: 100)
        let new = CPUTicks(user: 10, system: 0, idle: 120)
        #expect(abs(new.utilization(since: old).total - 50) < 0.001)
    }
    @Test func unchangedCPUHasNoNaN() {
        let ticks = CPUTicks(user: 1, system: 2, idle: 3)
        #expect(ticks.utilization(since: ticks).total == 0)
    }
    @Test func ratesUseElapsedTimeAnd64BitCounters() {
        let old = CounterPair(9_000_000_000, 5_000_000_000)
        let new = CounterPair(9_000_004_096, 5_000_001_024)
        let rate = new.rate(since: old, elapsed: 2)
        #expect(rate?.incoming == 2048)
        #expect(rate?.outgoing == 512)
    }
    @Test func newResetOrZeroIntervalCountersHaveNoRate() {
        #expect(CounterPair(100, 100).rate(since: nil, elapsed: 2) == nil)
        #expect(CounterPair(100, 100).rate(since: CounterPair(200, 100), elapsed: 2) == nil)
        #expect(CounterPair(100, 100).rate(since: CounterPair(), elapsed: 0) == nil)
    }
    @Test func memoryIncludesCompressedButExcludesCache() {
        var memory = MemoryMetrics()
        memory.total = 1000; memory.app = 300; memory.wired = 100; memory.compressed = 200; memory.cached = 250
        #expect(memory.used == 600)
        #expect(memory.available == 400)
        #expect(memory.percent == 60)
    }
    @Test func memoryClampsAndHandlesUnavailableTotal() {
        var memory = MemoryMetrics()
        #expect(memory.percent == 0)
        memory.total = 100; memory.app = 200
        #expect(memory.available == 0)
        #expect(memory.percent == 100)
    }
    @Test func processCPUUsesIntervalAndIdentity() {
        let old = ProcessCPUCounters(birthID: 10, nanoseconds: 1_000_000_000, uptime: 20)
        let new = ProcessCPUCounters(birthID: 10, nanoseconds: 6_000_000_000, uptime: 22)
        #expect(new.percent(since: old) == 250)
        #expect(new.percent(since: nil) == nil)
        #expect(new.percent(since: new) == nil)
        #expect(ProcessCPUCounters(birthID: 11, nanoseconds: 6_000_000_000, uptime: 22).percent(since: old) == nil)
        #expect(ProcessCPUCounters(birthID: 10, nanoseconds: 0, uptime: 22).percent(since: old) == nil)
    }
    @Test func formattingUnavailableAndUptime() {
        #expect(Format.rate(nil) == "—")
        #expect(Format.rate(2048) == "2.0 KB/s")
        #expect(Format.uptime(90061) == "1d 1h")
    }
}
