import Foundation
import IOKit

struct SystemPowerSample: Equatable, Sendable {
    let watts: Double
    let readAt: Date

    func isFresh(at now: Date, notBefore: Date? = nil) -> Bool {
        let age = now.timeIntervalSince(readAt)
        return (-5...90).contains(age) && (notBefore.map { readAt >= $0 } ?? true)
    }
}

struct SystemPowerReader: Sendable {
    /// Best-effort SMC system-total power (the PSTR sensor used by Stats).
    /// Apple does not publish a cross-model contract for this sensor. Read only;
    /// no helper, privileges, key enumeration, or persistent connection.
    func read() -> SystemPowerSample? {
        readSensors(system: true, input: false, battery: false).system
    }

    /// One short-lived connection per refresh; fixed read-only keys, no scanning.
    func readSensors(system: Bool, input: Bool, battery: Bool, temperature: Bool = false) ->
        (system: SystemPowerSample?, input: SystemPowerSample?, battery: BatteryPowerSample?,
         temperature: Double?) {
        let empty: (SystemPowerSample?, SystemPowerSample?, BatteryPowerSample?, Double?)
            = (nil, nil, nil, nil)
        guard system || input || battery || temperature else { return empty }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return empty }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return empty }
        defer { IOServiceClose(connection) }
        // SMC supplies no hardware timestamp. Record the start of the read so
        // an IPC call that stalls cannot make an old result appear fresh.
        let readAt = Date()
        let exchange: ([UInt8]) -> [UInt8]? = { request in
            var response = [UInt8](repeating: 0, count: 80)
            var size = response.count
            let result = request.withUnsafeBytes { input in
                response.withUnsafeMutableBytes { output in
                    IOConnectCallStructMethod(connection, 2, input.baseAddress, input.count,
                                              output.baseAddress, &size)
                }
            }
            return result == KERN_SUCCESS && size == 80 ? response : nil
        }
        let systemSample = system ? Self.readValue(sensor: .system, exchange: exchange)
            .map { SystemPowerSample(watts: $0, readAt: readAt) } : nil
        let inputSample = input ? Self.readValue(sensor: .input, exchange: exchange)
            .map { SystemPowerSample(watts: $0, readAt: readAt) } : nil
        var batterySample: BatteryPowerSample?
        // The captured integer battery-sensor ABI below is Apple Silicon.
        // Intel keeps the validated AppleSmartBattery voltage/current fallback.
        #if arch(arm64)
        if battery, let volts = Self.readValue(sensor: .batteryVoltage, exchange: exchange),
           let amps = Self.readValue(sensor: .batteryCurrent, exchange: exchange) {
            batterySample = BatteryPowerSample(volts: volts, amps: amps, updatedAt: readAt)
        }
        #endif
        // Battery temperature is one more fixed read-only key on the same
        // short-lived connection; it adds no scan and no sampling loop.
        let batteryTemperature = temperature
            ? Self.readValue(sensor: .batteryTemperature, exchange: exchange) : nil
        return (systemSample, inputSample, batterySample, batteryTemperature)
    }

    enum Sensor: UInt32 {
        case system = 0x50535452 // PSTR, system total
        case input = 0x50445452 // PDTR, adapter input
        case batteryCurrent = 0x42304143 // B0AC
        case batteryVoltage = 0x42304156 // B0AV
        case batteryTemperature = 0x54423054 // TB0T, battery temperature in °C
    }

    // AppleSMC's 80-byte key-data ABI: key 0, keyInfo size/type 28/32,
    // result 40, command 42, payload 48. Encode bytes explicitly rather than
    // relying on Swift struct padding. Host integers and flt are little-endian
    // on supported Macs; fixed-point sensor payloads are big-endian.
    static func readWatts(exchange: ([UInt8]) -> [UInt8]?) -> Double? {
        readValue(sensor: .system, exchange: exchange)
    }

    static func readValue(sensor: Sensor, exchange: ([UInt8]) -> [UInt8]?) -> Double? {
        var request = [UInt8](repeating: 0, count: 80)
        for offset in 0..<4 { request[offset] = UInt8(truncatingIfNeeded: sensor.rawValue >> (offset * 8)) }
        request[42] = 9 // read key info
        guard let info = exchange(request), info.count == 80, info[40] == 0 else { return nil }
        let size = littleEndianUInt32(info, at: 28)
        let type = littleEndianUInt32(info, at: 32)
        switch (type, size) {
        case (0x666c7420, 4), (0x66706532, 2), (0x73703738, 2): break // flt , fpe2, sp78
        case (0x73693136, 2) where sensor == .batteryCurrent: break // si16, mA
        case (0x75693136, 2) where sensor == .batteryVoltage: break // ui16, mV
        default: return nil
        }
        request.replaceSubrange(28..<32, with: info[28..<32])
        request[42] = 5 // read bytes (never issue write command 6)
        guard let response = exchange(request), response.count == 80, response[40] == 0 else { return nil }
        // Temperature keeps its own verified encoding/range rules in the pure
        // parser instead of reusing the power decode below.
        if sensor == .batteryTemperature {
            return BatteryHealthParser.temperatureCelsius(
                smcType: type,
                bytes: Array(response[48..<80])
            )
        }
        let watts: Double
        if type == 0x666c7420 {
            watts = Double(Float(bitPattern: littleEndianUInt32(response, at: 48)))
        } else if type == 0x73693136 || type == 0x75693136 {
            let raw = UInt16(response[48]) | UInt16(response[49]) << 8
            watts = (type == 0x73693136 ? Double(Int16(bitPattern: raw)) : Double(raw)) / 1_000
        } else {
            let raw = UInt16(response[48]) << 8 | UInt16(response[49])
            watts = type == 0x66706532 ? Double(raw) / 4 : Double(Int16(bitPattern: raw)) / 256
        }
        // An awake Mac cannot consume zero watts. Missing/invalid telemetry
        // must not masquerade as the valid 0 W of an idle battery.
        guard watts.isFinite else { return nil }
        switch sensor {
        case .system: return watts > 0 && watts <= 1_000 ? watts : nil
        case .input: return (0...1_000).contains(watts) ? watts : nil
        case .batteryCurrent: return abs(watts) <= 30 ? watts : nil
        case .batteryVoltage: return (1...30).contains(watts) ? watts : nil
        case .batteryTemperature: return nil // handled above
        }
    }

    private static func littleEndianUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }
}
