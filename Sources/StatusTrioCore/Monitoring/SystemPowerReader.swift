import Foundation
import IOKit

struct SystemPowerReader: SystemPowerReading {
    /// Best-effort SMC system-total power (the PSTR sensor used by Stats).
    /// Apple does not publish a cross-model contract for this sensor. Read only;
    /// no helper, privileges, key enumeration, or persistent connection.
    func read() -> SystemPowerSample? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
        defer { IOServiceClose(connection) }
        // SMC supplies no hardware timestamp. Record the start of the read so
        // an IPC call that stalls cannot make an old result appear fresh.
        let readAt = Date()
        guard let watts = Self.readWatts(exchange: { request in
            var response = [UInt8](repeating: 0, count: 80)
            var size = response.count
            let result = request.withUnsafeBytes { input in
                response.withUnsafeMutableBytes { output in
                    IOConnectCallStructMethod(connection, 2, input.baseAddress, input.count,
                                              output.baseAddress, &size)
                }
            }
            return result == KERN_SUCCESS && size == 80 ? response : nil
        }) else { return nil }
        return SystemPowerSample(watts: watts, readAt: readAt)
    }

    // AppleSMC's 80-byte key-data ABI: key 0, keyInfo size/type 28/32,
    // result 40, command 42, payload 48. Encode bytes explicitly rather than
    // relying on Swift struct padding. Host integers and flt are little-endian
    // on supported Macs; fixed-point sensor payloads are big-endian.
    static func readWatts(exchange: ([UInt8]) -> [UInt8]?) -> Double? {
        var request = [UInt8](repeating: 0, count: 80)
        request.replaceSubrange(0..<4, with: [0x52, 0x54, 0x53, 0x50]) // PSTR
        request[42] = 9 // read key info
        guard let info = exchange(request), info.count == 80, info[40] == 0 else { return nil }
        let size = littleEndianUInt32(info, at: 28)
        let type = littleEndianUInt32(info, at: 32)
        switch (type, size) {
        case (0x666c7420, 4), (0x66706532, 2), (0x73703738, 2): break // flt , fpe2, sp78
        default: return nil
        }
        request.replaceSubrange(28..<32, with: info[28..<32])
        request[42] = 5 // read bytes (never issue write command 6)
        guard let response = exchange(request), response.count == 80, response[40] == 0 else { return nil }
        let watts: Double
        if type == 0x666c7420 {
            watts = Double(Float(bitPattern: littleEndianUInt32(response, at: 48)))
        } else {
            let raw = UInt16(response[48]) << 8 | UInt16(response[49])
            watts = type == 0x66706532 ? Double(raw) / 4 : Double(Int16(bitPattern: raw)) / 256
        }
        // An awake Mac cannot consume zero watts. Missing/invalid telemetry
        // must not masquerade as the valid 0 W of an idle battery.
        return watts.isFinite && watts > 0 && watts <= 1_000 ? watts : nil
    }

    private static func littleEndianUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }
}
