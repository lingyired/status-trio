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

/// Reads per-interface byte counters and derives aggregate up/down throughput.
///
/// Uses `sysctl(NET_RT_IFLIST2)` (64-bit `if_data64` counters). Counts physical
/// `en*` interfaces that are UP and not loopback; only when a machine has no
/// `en*` interface does it fall back to other UP, non-loopback interfaces, and
/// even then it excludes virtual/VPN names (`utun`, `ipsec`, `ppp`, `awdl`, …).
/// Rates are computed per interface and only when the interface *set* is
/// unchanged, so plugging in an adapter or a VPN coming up cannot fabricate a
/// spike; instead the baseline is rebuilt and one sample reads as collecting.
final class NetworkThroughputReader: @unchecked Sendable {
    private static let minimumInterval: TimeInterval = 0.2
    private static let maximumInterval: TimeInterval = 15
    private static let virtualPrefixes = [
        "utun", "ipsec", "ppp", "awdl", "llw", "gif", "stf", "bridge",
        "ap", "vnic", "tap", "tun", "lo",
    ]

    private var previous: (totals: [String: InterfaceByteTotals], at: Date)?

    func read(at date: Date) -> NetworkThroughputReading? {
        guard let current = Self.readPerInterfaceTotals() else {
            previous = nil
            return nil
        }
        defer { previous = (current, date) }
        guard let previous else { return nil }
        return Self.rates(previous: previous.totals, previousAt: previous.at,
                          current: current, currentAt: date)
    }

    /// Aggregate rate math (kept for callers/tests that already have totals).
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

    /// Per-interface rate math. Returns nil for a bad interval, a changed
    /// interface set, or any counter going backwards, so the caller never shows
    /// a fake spike after a topology change.
    static func rates(previous: [String: InterfaceByteTotals], previousAt: Date,
                      current: [String: InterfaceByteTotals], currentAt: Date) -> NetworkThroughputReading? {
        let interval = currentAt.timeIntervalSince(previousAt)
        guard interval >= minimumInterval, interval <= maximumInterval else { return nil }
        guard Set(previous.keys) == Set(current.keys) else { return nil }
        var receivedDelta: UInt64 = 0
        var sentDelta: UInt64 = 0
        for key in previous.keys {
            guard let p = previous[key], let c = current[key] else { return nil }
            guard c.received >= p.received, c.sent >= p.sent else { return nil }
            receivedDelta += c.received - p.received
            sentDelta += c.sent - p.sent
        }
        return NetworkThroughputReading(
            downloadBytesPerSecond: Double(receivedDelta) / interval,
            uploadBytesPerSecond: Double(sentDelta) / interval,
            sampledAt: currentAt
        )
    }

    static func readPerInterfaceTotals() -> [String: InterfaceByteTotals]? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length: size_t = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else {
            return nil
        }
        return parsePerInterface(buffer, length: length)
    }

    /// Aggregate totals for the counted interfaces (compatibility helper).
    static func readInterfaceTotals() -> InterfaceByteTotals? {
        guard let perInterface = readPerInterfaceTotals() else { return nil }
        return sum(perInterface)
    }

    /// Aggregate totals parsed from a raw buffer (compatibility helper).
    static func parse(_ bytes: [UInt8], length: Int) -> InterfaceByteTotals? {
        guard let perInterface = parsePerInterface(bytes, length: length) else { return nil }
        return sum(perInterface)
    }

    private static func sum(_ perInterface: [String: InterfaceByteTotals]) -> InterfaceByteTotals? {
        guard !perInterface.isEmpty else { return nil }
        var received: UInt64 = 0
        var sent: UInt64 = 0
        for totals in perInterface.values {
            received &+= totals.received
            sent &+= totals.sent
        }
        return InterfaceByteTotals(received: received, sent: sent)
    }

    private static func isVirtual(_ name: String) -> Bool {
        virtualPrefixes.contains { name.hasPrefix($0) }
    }

    /// Parses the buffer into per-interface totals for the counted interfaces.
    static func parsePerInterface(_ bytes: [UInt8], length: Int) -> [String: InterfaceByteTotals]? {
        guard length > 0, bytes.count >= length else { return nil }
        var candidates: [String: InterfaceByteTotals] = [:]
        var sawEn = false

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
                    if isUp, !isLoopback, let name = interfaceName(index: info.ifm_index) {
                        let totals = InterfaceByteTotals(
                            received: info.ifm_data.ifi_ibytes,
                            sent: info.ifm_data.ifi_obytes)
                        if name.hasPrefix("en") {
                            candidates[name] = totals
                            sawEn = true
                        } else if !isVirtual(name) {
                            candidates[name] = totals
                        }
                    }
                }
                offset += messageLength
            }
        }

        if sawEn {
            return candidates.filter { $0.key.hasPrefix("en") }
        }
        let fallback = candidates.filter { !$0.key.hasPrefix("en") && !isVirtual($0.key) }
        return fallback.isEmpty ? nil : fallback
    }

    private static func interfaceName(index: UInt16) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
        guard if_indextoname(UInt32(index), &buffer) != nil else { return nil }
        return String(cString: buffer)
    }
}
