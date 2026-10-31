import Foundation
import Darwin
import IOKit

public struct SystemLoad: Codable, Equatable {
    public let cpuUsagePercent: Double?
    public let gpuUsagePercent: Double?

    public init(cpuUsagePercent: Double? = nil, gpuUsagePercent: Double? = nil) {
        self.cpuUsagePercent = cpuUsagePercent
        self.gpuUsagePercent = gpuUsagePercent
    }
}

/// System-wide readings. CPU is the active fraction across all logical CPUs.
/// GPU is the busiest reported accelerator's device utilization, not a sum of engines.
/// The lock protects the CPU baseline, so this reader can move between worker queues.
public final class SystemLoadReader: @unchecked Sendable {
    private let lock = NSLock()
    private var cpu: CPULoadAccumulator

    public init() {
        cpu = CPULoadAccumulator(processorCount: ProcessInfo.processInfo.activeProcessorCount,
                                 ticksPerSecond: max(1, sysconf(_SC_CLK_TCK)))
    }

    public func sample() -> SystemLoad {
        lock.lock(); defer { lock.unlock() }
        let usage = cpu.consume(Self.cpuTicks(), at: ProcessInfo.processInfo.systemUptime)
        return SystemLoad(cpuUsagePercent: usage, gpuUsagePercent: Self.gpuUsage())
    }

    /// Clear the CPU interval after sleep, pause or another sampling interruption.
    public func reset() {
        lock.lock(); defer { lock.unlock() }
        cpu.reset()
    }

    private static func cpuTicks() -> CPUTicks? {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let capacity = Int(count)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                host_statistics64(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS, count == capacity else { return nil }
        return CPUTicks(user: info.cpu_ticks.0, system: info.cpu_ticks.1,
                        idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
    }

    private static func gpuUsage() -> Double? {
        var values: [Double] = []
        var seen = Set<UInt64>()
        // IOAccelerator normally matches AGX subclasses as well. The second query
        // also covers drivers which only expose the more specific service class.
        for serviceClass in ["IOAccelerator", "AGXAccelerator"] {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(serviceClass), &iterator) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }
            while true {
                let service = IOIteratorNext(iterator)
                guard service != 0 else { break }
                defer { IOObjectRelease(service) }
                var identity: UInt64 = 0
                if IORegistryEntryGetRegistryEntryID(service, &identity) == KERN_SUCCESS {
                    guard seen.insert(identity).inserted else { continue }
                }
                guard let property = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
                      let statistics = property as? [String: Any],
                      let value = GPUUsageDecoder.percentage(statistics) else { continue }
                values.append(value)
            }
        }
        return values.max()
    }
}

struct CPUTicks: Equatable {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32

    var values: [UInt32] { [user, system, idle, nice] }
}

struct CPULoadAccumulator {
    private var previous: (ticks: CPUTicks, time: TimeInterval)?
    private let processorCount: Int
    private let ticksPerSecond: Int

    init(processorCount: Int, ticksPerSecond: Int) {
        self.processorCount = max(1, processorCount)
        self.ticksPerSecond = max(1, ticksPerSecond)
    }

    mutating func reset() { previous = nil }

    mutating func consume(_ ticks: CPUTicks?, at time: TimeInterval) -> Double? {
        guard let ticks, time.isFinite else { reset(); return nil }
        let baseline = previous
        previous = (ticks, time)
        guard let baseline else { return nil }
        let elapsed = time - baseline.time
        // Long gaps describe a different interval than the current live reading.
        guard elapsed > 0, elapsed <= 120 else { return nil }
        var deltas: [UInt64] = []
        for (old, new) in zip(baseline.ticks.values, ticks.values) {
            if new >= old { deltas.append(UInt64(new - old)) }
            else if old >= 0xf0000000, new <= 0x0fffffff {
                deltas.append(UInt64(UInt32.max) - UInt64(old) + UInt64(new) + 1)
            } else { return nil }
        }
        let total = deltas.reduce(0, +)
        // A reset can resemble a UInt32 rollover. Reject physically implausible jumps.
        let maximum = elapsed * Double(processorCount * ticksPerSecond) * 2 + Double(processorCount * 10)
        guard total > 0, Double(total) <= maximum else { return nil }
        let active = total - deltas[2]
        return Double(active) / Double(total) * 100
    }
}

enum GPUUsageDecoder {
    static func percentage(_ statistics: [String: Any]) -> Double? {
        // Device Utilization is published by Apple/Intel/AMD drivers. Other drivers
        // publish GPU Activity(%) instead. Per-engine renderer/tiler
        // percentages are deliberately not added together or presented as a device total.
        for key in ["Device Utilization %", "GPU Activity(%)"] {
            guard let value = statistics[key] as? NSNumber,
                  CFGetTypeID(value) != CFBooleanGetTypeID() else { continue }
            let number = value.doubleValue
            if number.isFinite, (0...100).contains(number) { return number }
        }
        return nil
    }
}
