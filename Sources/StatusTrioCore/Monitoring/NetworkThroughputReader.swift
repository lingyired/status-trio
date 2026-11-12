import Foundation
import Darwin

/// One aggregate throughput sample for the physical interfaces.
struct NetworkThroughputReading: Equatable, Sendable {
    var downloadBytesPerSecond: Double
    var uploadBytesPerSecond: Double
    var sampledAt: Date
}

/// Cumulative byte totals across the interfaces we count.
struct InterfaceByteTotals: Equatable, Sendable {
    var received: UInt64
    var sent: UInt64
}

/// Reads aggregate interface byte counters and derives up/down throughput.
///
/// Uses `sysctl(NET_RT_IFLIST2)` which returns 64-bit `if_data64` counters, so
/// fast links do not wrap the way the 32-bit `getifaddrs` `if_data` would.
/// Counts physical `en*` interfaces that are UP and not loopback; if a machine
/// has no `en*` interface it falls back to every non-loopback UP interface.
/// The reader keeps its own previous sample, so a missing/invalid interval
/// yields `nil` (the caller reports `collecting`) instead of a bogus rate.
final class NetworkThroughputReader: @unchecked Sendable {
    private static let minimumInterval: TimeInterval = 0.2
    private static let maximumInterval: TimeInterval = 15

    private var previous: (totals: InterfaceByteTotals, at: Date)?

    func read(at date: Date) -> NetworkThroughputReading? {
        guard let current = Self.readInterfaceTotals() else {
            previous = nil
            return nil
        }
        defer { previous = (current, date) }
        guard let previous else { return nil }
        return Self.rates(previous: previous.totals, previousAt: previous.at,
                          current: current, currentAt: date)
    }

    /// Pure rate math. Returns `nil` when the interval is unusable or the
    /// counters go backwards (reset/wrap) so the caller never shows a fake spike.
    static func rates(previous: InterfaceByteTotals, previousAt: Date,
                      current: InterfaceByteTotals, currentAt: Date) -> NetworkThroughputReading? {
        let interval = currentAt.timeIntervalSince(previousAt)
        guard interval >= minimumInterval, interval <= maximumInterval else { return nil }
        guard current.received >= previous.received, current.sent >= previous.sent else { return nil }
        return NetworkThroughputReading(
            downloadBytesPerSecond: Double(current.received - previous.received) / interval,
            uploadBytesPerSecond: Double(current.sent - previous.sent) / interval,
            sampledAt: currentAt
        )
    }

    /// Reads the current cumulative totals, summing the interfaces we count.
    static func readInterfaceTotals() -> InterfaceByteTotals? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length: size_t = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else {
            return nil
        }
        return parse(buffer, length: length)
    }

    /// Parses an `NET_RT_IFLIST2` buffer and sums `en*` interfaces (or all
    /// non-loopback interfaces when none are named `en*`).
    static func parse(_ bytes: [UInt8], length: Int) -> InterfaceByteTotals? {
        guard length > 0, bytes.count >= length else { return nil }
        var enReceived: UInt64 = 0
        var enSent: UInt64 = 0
        var sawEn = false
        var allReceived: UInt64 = 0
        var allSent: UInt64 = 0
        var sawAny = false

        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = base.advanced(by: offset).assumingMemoryBound(to: if_msghdr.self).pointee
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0, offset + messageLength <= length else { break }
                if header.ifm_type == UInt16(RTM_IFINFO2),
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let info = base.advanced(by: offset).assumingMemoryBound(to: if_msghdr2.self).pointee
                    let flags = info.ifm_flags
                    let isUp = (flags & IFF_UP) != 0
                    let isLoopback = (flags & IFF_LOOPBACK) != 0
                    if isUp, !isLoopback {
                        let received = info.ifm_data.ifi_ibytes
                        let sent = info.ifm_data.ifi_obytes
                        allReceived &+= received
                        allSent &+= sent
                        sawAny = true
                        if interfaceName(index: info.ifm_index)?.hasPrefix("en") == true {
                            enReceived &+= received
                            enSent &+= sent
                            sawEn = true
                        }
                    }
                }
                offset += messageLength
            }
        }

        if sawEn {
            return InterfaceByteTotals(received: enReceived, sent: enSent)
        }
        return sawAny ? InterfaceByteTotals(received: allReceived, sent: allSent) : nil
    }

    private static func interfaceName(index: UInt16) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
        guard if_indextoname(UInt32(index), &buffer) != nil else { return nil }
        return String(cString: buffer)
    }
}
