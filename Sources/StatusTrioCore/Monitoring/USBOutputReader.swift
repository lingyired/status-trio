import Foundation

/// A USB / Thunderbolt port that is currently sourcing power to an accessory.
///
/// The live sample is SMC channels D1–D4, `DnJV` × `DnJI`. `PowerOutDetails`
/// is the fallback when those fixed keys do not answer, and is absent when
/// nothing is attached.
///
/// Only `Watts` is a measured output: on Mac15,9 / macOS 27.2 it matched
/// `Current × AdapterVoltage` within 0.2% (2461 mW vs 2457 mW) for a hub. The
/// sibling `PDPowermW` is the negotiated PD contract (that port: 15000 mW for
/// 5V × 3A), not what the accessory draws, so it is never substituted for a
/// missing measurement. Other read-only tools draw the same line: WhatCable
/// labels `PDPowermW` "PD contract negotiated power", and battery-monitor reads
/// only `Watts`; macpow's `Watts > 0 ? Watts : PDPowermW` fallback is the
/// behaviour this avoids.
struct USBOutputSample: Equatable, Sendable {
    let watts: Double
    let readAt: Date
    let portCount: Int

    func isFresh(at now: Date, notBefore: Date? = nil) -> Bool {
        let age = now.timeIntervalSince(readAt)
        return (-5...30).contains(age) && (notBefore.map { readAt >= $0 } ?? true)
    }
}

/// SMC D1–D4 accessory rails. `.unavailable` means none of the fixed keys
/// answered, which is different from an answered rail sitting at idle. The
/// measured case carries the SMC read-start time so a stalled read cannot make
/// an old rail value look fresh.
enum PortOutputRails: Equatable, Sendable {
    case unavailable
    case measured(watts: [Double], readAt: Date)
}

enum USBOutputReader {
    /// Idle CC/VConn rails on Mac16,1 sat at 0.05–0.14 W. The first Apple Watch
    /// charge pulse on that machine was 0.60 W, so anything quieter is not
    /// treated as power delivered to an accessory.
    static let chargingFloorWatts = 0.20

    /// Prefer a live SMC rail. An answered rail that is only idling stays
    /// hidden; it must not be replaced by a frozen `PowerOutDetails` value.
    static func resolve(portRails: PortOutputRails, registry: [String: Any], now: Date = Date()) -> USBOutputSample? {
        switch portRails {
        case .unavailable:
            return parse(registry: registry, now: now)
        case .measured(let rails, let readAt):
            let active = rails.filter { $0 >= chargingFloorWatts }
            guard !active.isEmpty else { return nil }
            let total = active.reduce(0, +)
            guard total <= 300 else { return nil }
            // Keep the SMC read-start, not `now`, so a stalled refresh cannot
            // pass this reading off as fresh to the breakdown's staleness check.
            return USBOutputSample(watts: total, readAt: readAt, portCount: active.count)
        }
    }

    /// Ports that are powering an accessory, summed into one output reading.
    /// A port without a measured `Watts` value is skipped, not filled in from
    /// the PD contract. Values outside a plausible single-port envelope are
    /// treated as "this key is not a live output reading" rather than as power.
    static func parse(registry: [String: Any], now: Date = Date()) -> USBOutputSample? {
        guard let ports = registry["PowerOutDetails"] as? [[String: Any]], !ports.isEmpty else { return nil }
        var total = 0.0
        var counted = 0
        for port in ports {
            guard let milliwatts = number(port["Watts"]) else { continue }
            let watts = milliwatts / 1_000
            guard watts.isFinite, (0...150).contains(watts) else { continue }
            total += watts
            counted += 1
        }
        guard counted > 0, total <= 300 else { return nil }
        return USBOutputSample(watts: total, readAt: now, portCount: counted)
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let value as Double: return value
        case let value as Int: return Double(value)
        case let value as NSNumber: return value.doubleValue
        default: return nil
        }
    }
}
