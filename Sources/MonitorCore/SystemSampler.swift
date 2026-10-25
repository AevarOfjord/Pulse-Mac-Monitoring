import Foundation
import Darwin
import IOKit

/// All sampling and subprocess work is isolated from the UI thread.
public actor SystemSampler {
    private var previousCPU: [CPUTicks] = []
    private var previousNetwork: [String: CounterPair] = [:]
    private var previousDisk: [UInt64: CounterPair] = [:]
    private var previousTime: Double?
    private let host = mach_host_self()

    public init() {}
    deinit { mach_port_deallocate(mach_task_self_, host) }

    public func resetBaselines() {
        previousCPU = []; previousNetwork = [:]; previousDisk = [:]; previousTime = nil
    }

    public func sample() -> SystemSnapshot {
        var snapshot = SystemSnapshot()
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = previousTime.map { now - $0 } ?? 0
        snapshot.uptime = now
        let ticks = cpuTicks()
        if let ticks {
            if ticks.count == previousCPU.count, !ticks.isEmpty {
                let values = zip(ticks, previousCPU).map { $0.utilization(since: $1) }
                snapshot.cores = values.map(\.total)
                snapshot.cpu = values.map(\.total).reduce(0, +) / Double(values.count)
                snapshot.cpuUser = values.map(\.user).reduce(0, +) / Double(values.count)
                snapshot.cpuSystem = values.map(\.system).reduce(0, +) / Double(values.count)
            }
            previousCPU = ticks
        } else { snapshot.errors.append("CPU sampling is unavailable."); previousCPU = [] }
        snapshot.memory = memoryMetrics()
        if snapshot.memory == nil { snapshot.errors.append("Memory statistics are unavailable.") }
        snapshot.gpu = gpuMetrics()
        snapshot.disk = diskMetrics(elapsed: elapsed)
        let network = networkMetrics(elapsed: elapsed)
        snapshot.interfaces = network
        let ready = network.compactMap(\.rate)
        if !ready.isEmpty {
            snapshot.network = CounterRate(incoming: ready.reduce(0) { $0 + $1.incoming },
                                           outgoing: ready.reduce(0) { $0 + $1.outgoing })
        }
        var averages = [Double](repeating: 0, count: 3)
        if getloadavg(&averages, 3) == 3 { snapshot.loadAverage = averages }
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: snapshot.thermal = "Nominal"
        case .fair: snapshot.thermal = "Fair"
        case .serious: snapshot.thermal = "Serious"
        case .critical: snapshot.thermal = "Critical"
        @unknown default: snapshot.thermal = "Unknown"
        }
        previousTime = now
        return snapshot
    }

    private func cpuTicks() -> [CPUTicks]? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer { vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)) }
        return (0..<Int(count)).map { index in
            let offset = index * Int(CPU_STATE_MAX)
            return CPUTicks(user: UInt32(bitPattern: info[offset + Int(CPU_STATE_USER)]),
                            system: UInt32(bitPattern: info[offset + Int(CPU_STATE_SYSTEM)]),
                            idle: UInt32(bitPattern: info[offset + Int(CPU_STATE_IDLE)]),
                            nice: UInt32(bitPattern: info[offset + Int(CPU_STATE_NICE)]))
        }
    }

    private func memoryMetrics() -> MemoryMetrics? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }
        let page = UInt64(pageSize)
        var memory = MemoryMetrics()
        memory.total = ProcessInfo.processInfo.physicalMemory
        memory.app = UInt64(stats.internal_page_count > stats.purgeable_count ? stats.internal_page_count - stats.purgeable_count : 0) * page
        memory.wired = UInt64(stats.wire_count) * page
        memory.compressed = UInt64(stats.compressor_page_count) * page
        memory.cached = UInt64(stats.external_page_count) * page + UInt64(stats.purgeable_count) * page
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 { memory.swapUsed = swap.xsu_used }
        var pressure: Int32 = 0
        size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &size, nil, 0) == 0 {
            switch pressure {
            case 1: memory.pressure = "Normal"
            case 2: memory.pressure = "Warning"
            case 4: memory.pressure = "Critical"
            default: memory.pressure = "Unknown"
            }
        }
        return memory
    }

    private func gpuMetrics() -> GPUMetrics {
        var gpu = GPUMetrics()
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return gpu }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            // Fetch only the small statistics dictionary, never the full registry tree.
            let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any]
            let value = (stats?["Device Utilization %"] as? NSNumber)?.doubleValue
            // On multi-GPU Macs, display the busiest available accelerator.
            guard gpu.utilization == nil || (value ?? -1) > (gpu.utilization ?? -1) else { continue }
            gpu.utilization = value.map { min(100, max(0, $0)) }
            gpu.renderer = (stats?["Renderer Utilization %"] as? NSNumber)?.doubleValue
            gpu.tiler = (stats?["Tiler Utilization %"] as? NSNumber)?.doubleValue
            gpu.memoryUsed = (stats?["In use system memory"] as? NSNumber)?.uint64Value
            gpu.cores = (IORegistryEntryCreateCFProperty(service, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.intValue
            if let name = IORegistryEntryCreateCFProperty(service, "model" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String { gpu.name = name }
        }
        return gpu
    }

    private func diskMetrics(elapsed: Double) -> DiskMetrics {
        var disk = DiskMetrics()
        let data = URL(fileURLWithPath: "/System/Volumes/Data")
        if let values = try? data.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
           let total = values.volumeTotalCapacity, let free = values.volumeAvailableCapacity {
            disk.total = UInt64(max(0, total)); disk.available = UInt64(max(0, free))
        }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else { return disk }
        defer { IOObjectRelease(iterator) }
        var current: [UInt64: CounterPair] = [:]
        var rates: [CounterRate] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS,
                  let stats = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
                  let read = stats["Bytes (Read)"] as? NSNumber,
                  let write = stats["Bytes (Write)"] as? NSNumber else { continue }
            let counters = CounterPair(read.uint64Value, write.uint64Value)
            current[id] = counters
            if let rate = counters.rate(since: previousDisk[id], elapsed: elapsed) { rates.append(rate) }
        }
        previousDisk = current
        if !rates.isEmpty { disk.activity = CounterRate(incoming: rates.reduce(0) { $0 + $1.incoming }, outgoing: rates.reduce(0) { $0 + $1.outgoing }) }
        return disk
    }

    private func networkMetrics(elapsed: Double) -> [NetworkInterface] {
        // NET_RT_IFLIST2 exposes 64-bit byte counters. getifaddrs uses 32-bit counters
        // on Darwin, which wrap after just 4 GiB of traffic.
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else {
            previousNetwork = [:]; return []
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, u_int(mib.count), &buffer, &size, nil, 0) == 0 else {
            previousNetwork = [:]; return []
        }
        var current: [String: CounterPair] = [:]
        buffer.withUnsafeBytes { bytes in
            var offset = 0
            while offset + 4 <= size {
                let length = Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard length >= 4, offset + length <= size else { break }
                defer { offset += length }
                guard bytes[offset + 3] == UInt8(RTM_IFINFO2), length >= MemoryLayout<if_msghdr2>.size else { continue }
                let message = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                guard message.ifm_flags & IFF_UP != 0 else { continue }
                var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                guard if_indextoname(UInt32(message.ifm_index), &nameBuffer) != nil else { continue }
                let name = String(cString: nameBuffer)
                guard name.hasPrefix("en") else { continue }
                current[name] = CounterPair(message.ifm_data.ifi_ibytes, message.ifm_data.ifi_obytes)
            }
        }
        let result = current.sorted { $0.key < $1.key }.map { name, pair in
            NetworkInterface(name: name, rate: pair.rate(since: previousNetwork[name], elapsed: elapsed),
                             received: pair.incoming, sent: pair.outgoing)
        }
        previousNetwork = current
        return result
    }

    public func processes() -> [ProcessMetric] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-A", "-o", "pid=,pcpu=,rss=,comm="]
        process.environment = ["LC_ALL": "C", "PATH": "/usr/bin:/bin"]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output; process.standardError = errors
        do { try process.run() } catch { return [] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap(ProcessMetric.parse).sorted { $0.cpu > $1.cpu }
    }

    public static func hardwareName() -> String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return "Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else { return "Mac" }
        return String(cString: buffer)
    }
}
