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
    /// Total of `ports`, kept as its own field because the breakdown residual
    /// subtracts one number.
    let watts: Double
    let readAt: Date
    /// One entry per port that is powering something, in channel order.
    let ports: [USBPortOutput]

    var portCount: Int { ports.count }

    init(watts: Double, readAt: Date, ports: [USBPortOutput]) {
        self.watts = watts
        self.readAt = readAt
        self.ports = ports
    }

    func isFresh(at now: Date, notBefore: Date? = nil) -> Bool {
        let age = now.timeIntervalSince(readAt)
        return (-5...30).contains(age) && (notBefore.map { readAt >= $0 } ?? true)
    }
}

/// One port's live output. `channel` is the SMC `Dn` index (or the
/// `PowerOutDetails` `PortIndex` on the fallback path); `name` is the attached
/// accessory as USB reports it, filled in from `USBPortTopology`.
struct USBPortOutput: Equatable, Sendable {
    let channel: Int
    let watts: Double
    var name: String? = nil
}

/// One answered SMC accessory channel: `DnJV` × `DnJI` for channel `n`.
struct PortRail: Equatable, Sendable {
    let channel: Int
    let watts: Double
}

/// SMC D1–D4 accessory rails. `.unavailable` means none of the fixed keys
/// answered, which is different from an answered rail sitting at idle. The
/// measured case carries the SMC read-start time so a stalled read cannot make
/// an old rail value look fresh.
enum PortOutputRails: Equatable, Sendable {
    case unavailable
    case measured(rails: [PortRail], readAt: Date)
}

enum USBOutputReader {
    /// Idle CC/VConn rails on Mac16,1 sat at 0.05–0.14 W. The first Apple Watch
    /// charge pulse on that machine was 0.60 W, so anything quieter is not
    /// treated as power delivered to an accessory.
    static let chargingFloorWatts = 0.20

    /// Prefer a live SMC rail. An answered rail that is only idling stays
    /// hidden; it must not be replaced by a frozen `PowerOutDetails` value.
    ///
    /// With a topology, each port is named after its accessory, and the port
    /// the Mac is charging from is dropped: a sink port's rail is not output
    /// to an accessory, whatever it reads.
    static func resolve(portRails: PortOutputRails, registry: [String: Any],
                        topology: USBPortTopology? = nil, now: Date = Date()) -> USBOutputSample? {
        let sample: USBOutputSample?
        switch portRails {
        case .unavailable:
            sample = parse(registry: registry, now: now)
        case .measured(let rails, let readAt):
            let active = rails.filter { $0.watts >= chargingFloorWatts }
                .map { USBPortOutput(channel: $0.channel, watts: $0.watts) }
            // Keep the SMC read-start, not `now`, so a stalled refresh cannot
            // pass this reading off as fresh to the breakdown's staleness check.
            sample = make(active, readAt: readAt)
        }
        guard let sample, let topology else { return sample }
        let labelled = sample.ports
            .filter { $0.channel != topology.inputChannel }
            .map { port -> USBPortOutput in
                var port = port
                port.name = topology.name(forChannel: port.channel)
                return port
            }
        return make(labelled, readAt: sample.readAt)
    }

    /// Whether a refresh has any output worth naming, before labels are read.
    static func hasOutput(_ portRails: PortOutputRails, registry: [String: Any]) -> Bool {
        resolve(portRails: portRails, registry: registry) != nil
    }

    private static func make(_ ports: [USBPortOutput], readAt: Date) -> USBOutputSample? {
        guard !ports.isEmpty else { return nil }
        let total = ports.reduce(0) { $0 + $1.watts }
        guard total <= 300 else { return nil }
        return USBOutputSample(watts: total, readAt: readAt, ports: ports)
    }

    /// Ports that are powering an accessory, summed into one output reading.
    /// A port without a measured `Watts` value is skipped, not filled in from
    /// the PD contract. Values outside a plausible single-port envelope are
    /// treated as "this key is not a live output reading" rather than as power.
    static func parse(registry: [String: Any], now: Date = Date()) -> USBOutputSample? {
        guard let ports = registry["PowerOutDetails"] as? [[String: Any]], !ports.isEmpty else { return nil }
        var outputs: [USBPortOutput] = []
        for (offset, port) in ports.enumerated() {
            guard let milliwatts = number(port["Watts"]) else { continue }
            let watts = milliwatts / 1_000
            guard watts.isFinite, (0...150).contains(watts) else { continue }
            // Same idle floor as the live rails: a quiescent port must not be
            // drawn, or named, as an accessory drawing power.
            guard watts >= chargingFloorWatts else { continue }
            // `PortIndex` is 1-based and matched the SMC channel numbers on
            // Mac16,1 (index 1 and D1 both carried the Watch charger).
            let channel = number(port["PortIndex"]).map { Int($0) } ?? offset + 1
            outputs.append(USBPortOutput(channel: channel, watts: watts))
        }
        return make(outputs, readAt: now)
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
