import Foundation

struct SystemPowerSample: Equatable, Sendable {
    let watts: Double
    let readAt: Date

    func isFresh(at now: Date, notBefore: Date? = nil) -> Bool {
        let age = now.timeIntervalSince(readAt)
        return (-5...90).contains(age) && (notBefore.map { readAt >= $0 } ?? true)
    }
}

/// One refresh's worth of SMC power sensors. Every field is a best-effort
/// reading from the same short-lived connection.
struct PowerSensorReadings: Equatable, Sendable {
    var system: SystemPowerSample?
    var input: SystemPowerSample?
    var battery: BatteryPowerSample?
    /// Built-in display backlight power (`PDBR`); `PBwo` on newer chips is not
    /// read yet, so machines without `PDBR` simply report nil.
    var display: SystemPowerSample?
    /// Accessory output on SMC channels D1–D4 (`DnJV` volts × `DnJI` amps).
    var portRails: PortOutputRails = .unavailable

    static let empty = Self()
}

struct SystemPowerReader: Sendable {
    /// Best-effort SMC system-total power (the PSTR sensor used by Stats).
    /// Apple does not publish a cross-model contract for this sensor. Read only;
    /// no helper, privileges, key enumeration, or persistent connection.
    func read() -> SystemPowerSample? {
        readSensors(system: true, input: false, battery: false).system
    }

    /// One short-lived connection per refresh; fixed read-only keys, no scanning.
    func readSensors(system: Bool, input: Bool, battery: Bool, breakdown: Bool = false) -> PowerSensorReadings {
        guard system || input || battery || breakdown else { return .empty }
        // Record the start so a slow IPC call cannot make old data look fresh.
        let readAt = Date()
        return SMCReadOnlyClient.withConnection { exchange in
            var readings = PowerSensorReadings.empty
            if system, let watts = Self.readValue(sensor: .system, exchange: exchange) {
                readings.system = SystemPowerSample(watts: watts, readAt: readAt)
            }
            if input, let watts = Self.readValue(sensor: .input, exchange: exchange) {
                readings.input = SystemPowerSample(watts: watts, readAt: readAt)
            }
            // The captured integer battery-sensor ABI below is Apple Silicon.
            // Intel keeps the validated AppleSmartBattery voltage/current fallback.
            #if arch(arm64)
            if battery, let volts = Self.readValue(sensor: .batteryVoltage, exchange: exchange),
               let amps = Self.readValue(sensor: .batteryCurrent, exchange: exchange) {
                readings.battery = BatteryPowerSample(volts: volts, amps: amps, updatedAt: readAt)
            }
            #endif
            if breakdown, let watts = Self.readValue(sensor: .display, exchange: exchange) {
                readings.display = SystemPowerSample(watts: watts, readAt: readAt)
            }
            if breakdown { readings.portRails = Self.readPortOutput(exchange: exchange, readAt: readAt) }
            return readings
        } ?? .empty
    }

    enum Sensor: UInt32 {
        case system = 0x50535452 // PSTR, system total
        case input = 0x50445452 // PDTR, adapter input
        case display = 0x50444252 // PDBR, built-in display backlight
        case batteryCurrent = 0x42304143 // B0AC
        case batteryVoltage = 0x42304156 // B0AV
    }

    static func readWatts(exchange: SMCReadOnlyClient.Exchange) -> Double? {
        readValue(sensor: .system, exchange: exchange)
    }

    static func readValue(sensor: Sensor, exchange: SMCReadOnlyClient.Exchange) -> Double? {
        guard let data = SMCReadOnlyClient.read(key: sensor.rawValue, exchange: exchange) else { return nil }
        switch (data.type, data.size) {
        case (0x666c7420, 4), (0x66706532, 2), (0x73703738, 2): break
        case (0x73693136, 2) where sensor == .batteryCurrent: break
        case (0x75693136, 2) where sensor == .batteryVoltage: break
        default: return nil
        }
        guard let value = SMCReadOnlyClient.decode(data, integerEncoding: .batteryLittleEndianMilliUnits) else { return nil }
        switch sensor {
        case .system: return value > 0 && value <= 1_000 ? value : nil
        case .input: return (0...1_000).contains(value) ? value : nil
        case .batteryCurrent: return abs(value) <= 30 ? value : nil
        case .batteryVoltage: return (1...30).contains(value) ? value : nil
        case .display: return (0...150).contains(value) ? value : nil
        }
    }

    /// Live accessory output on D1–D4. A key-info acknowledgement still
    /// counts when bytes cannot decode, preserving the frozen-data fallback
    /// boundary. Zero is a valid idle port, unlike system-total power.
    static func readPortOutput(exchange: SMCReadOnlyClient.Exchange, readAt: Date = Date()) -> PortOutputRails {
        var rails: [Double] = []
        var answered = false
        for channel in 1...4 {
            let volts = readScalar(key: portRailKey(channel: channel, voltage: true), exchange: exchange)
            let amps = readScalar(key: portRailKey(channel: channel, voltage: false), exchange: exchange)
            if volts.acknowledged || amps.acknowledged { answered = true }
            guard let volts = volts.value, let amps = amps.value else { continue }
            let watts = volts * amps
            guard watts.isFinite, (0...150).contains(watts) else { continue }
            rails.append(watts)
        }
        return answered ? .measured(watts: rails, readAt: readAt) : .unavailable
    }

    static func portRailKey(channel: Int, voltage: Bool) -> UInt32 {
        let suffix: UInt32 = voltage ? 0x4A56 : 0x4A49
        return (0x44 << 24) | (UInt32(0x30 + channel) << 16) | suffix
    }

    static func readScalar(key: UInt32, exchange: SMCReadOnlyClient.Exchange) -> (acknowledged: Bool, value: Double?) {
        var acknowledged = false
        let data = SMCReadOnlyClient.read(key: key, exchange: exchange, didAcknowledge: { acknowledged = true })
        guard let data else { return (acknowledged, nil) }
        switch (data.type, data.size) {
        case (0x666c7420, 4), (0x66706532, 2), (0x73703738, 2):
            return (acknowledged, SMCReadOnlyClient.decode(data))
        default:
            return (acknowledged, nil)
        }
    }
}
