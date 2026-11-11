import Foundation
import Darwin

struct CPUReading: Equatable, Sendable {
    /// Percent, 0...100. Aggregated by elapsed ticks, not by averaging cores.
    let usage: Double
    let perCoreUsage: [Double]
    let sampledAt: Date
}

struct CPUTicks: Equatable, Sendable {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32
}

/// Value state owned by the service's serial sampling queue.
struct CPUReader: Sendable {
    private var previous: [CPUTicks]?
    private var previousAt: Date?

    mutating func reset() {
        previous = nil
        previousAt = nil
    }

    mutating func read(at date: Date = Date()) -> CPUReading? {
        guard let ticks = Self.readTicks() else {
            reset()
            return nil
        }
        return sample(ticks, at: date)
    }

    /// Pure differential seam; preserves each 32-bit counter until after wrap
    /// handling. Long gaps (including sleep) and resets establish a new baseline.
    mutating func sample(_ ticks: [CPUTicks], at date: Date) -> CPUReading? {
        let old = previous
        let oldAt = previousAt
        defer {
            previous = ticks.isEmpty ? nil : ticks
            previousAt = ticks.isEmpty ? nil : date
        }
        guard !ticks.isEmpty, let old, let oldAt, old.count == ticks.count,
              date.timeIntervalSince(oldAt) > 0, date.timeIntervalSince(oldAt) <= 15 else { return nil }
        var totalBusy: UInt64 = 0
        var totalTicks: UInt64 = 0
        var cores: [Double] = []
        for (current, prior) in zip(ticks, old) {
            guard let user = Self.delta(current.user, prior.user),
                  let system = Self.delta(current.system, prior.system),
                  let nice = Self.delta(current.nice, prior.nice),
                  let idle = Self.delta(current.idle, prior.idle) else { return nil }
            let busy = user + system + nice
            let total = busy + idle
            // No ticks is not a measured 0%. Rebaseline the entire frame.
            guard total > 0 else { return nil }
            cores.append(Double(busy) / Double(total) * 100)
            totalBusy += busy
            totalTicks += total
        }
        guard totalTicks > 0 else { return nil }
        return CPUReading(usage: Double(totalBusy) / Double(totalTicks) * 100,
                          perCoreUsage: cores, sampledAt: date)
    }

    private static func delta(_ current: UInt32, _ previous: UInt32) -> UInt64? {
        if current >= previous { return UInt64(current - previous) }
        // Only a counter close to UInt32.max rolling over near zero is a wrap.
        // An ordinary backwards jump is a reset, never a huge utilization delta.
        guard previous >= 0xf000_0000, current <= 0x0fff_ffff else { return nil }
        return UInt64(current &- previous)
    }

    private static func readTicks() -> [CPUTicks]? {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            // infoCount is integer_t elements, NOT logical-core count.
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size))
        }
        let stride = Int(CPU_STATE_MAX)
        guard count > 0, Int(infoCount) >= Int(count) * stride else { return nil }
        return (0..<Int(count)).map { core in
            let offset = core * stride
            return CPUTicks(user: UInt32(bitPattern: info[offset + Int(CPU_STATE_USER)]),
                            system: UInt32(bitPattern: info[offset + Int(CPU_STATE_SYSTEM)]),
                            idle: UInt32(bitPattern: info[offset + Int(CPU_STATE_IDLE)]),
                            nice: UInt32(bitPattern: info[offset + Int(CPU_STATE_NICE)]))
        }
    }
}
