import Foundation
import IOKit

/// Shared, fixed-key AppleSMC protocol. Callers own the sampling cadence; a
/// connection exists only for the duration of `withConnection`. No key-table
/// enumeration or write command is exposed.
enum SMCReadOnlyClient {
    typealias Exchange = ([UInt8]) -> [UInt8]?

    struct Value {
        let type: UInt32
        let size: UInt32
        let payload: [UInt8]
    }

    enum IntegerEncoding {
        case bigEndian
        /// B0AC/B0AV on Apple Silicon use LE milli-amps/volts. This is a
        /// battery-specific ABI, not the interpretation of generic SMC integers.
        case batteryLittleEndianMilliUnits
    }

    static func withConnection<T>(_ body: (Exchange) -> T) -> T? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
        defer { IOServiceClose(connection) }
        return body { request in
            guard request.count == 80, request[42] == 9 || request[42] == 5 else { return nil }
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
    }

    static func key(_ name: String) -> UInt32? {
        let bytes = Array(name.utf8)
        guard bytes.count == 4, bytes.allSatisfy({ $0 < 128 }) else { return nil }
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    // Explicit 80-byte ABI: key 0, size/type 28/32, result 40, command 42,
    // payload 48. FourCharCode UInt32 fields travel little endian on Macs.
    static func read(key: UInt32, exchange: Exchange, didAcknowledge: () -> Void = {}) -> Value? {
        var request = [UInt8](repeating: 0, count: 80)
        for offset in 0..<4 { request[offset] = UInt8(truncatingIfNeeded: key >> (offset * 8)) }
        request[42] = 9
        guard let info = exchange(request), info.count == 80, info[40] == 0 else { return nil }
        didAcknowledge()
        let size = littleEndianUInt32(info, at: 28)
        guard (1...32).contains(size) else { return nil }
        let type = littleEndianUInt32(info, at: 32)
        request.replaceSubrange(28..<32, with: info[28..<32])
        request[42] = 5
        guard let response = exchange(request), response.count == 80, response[40] == 0 else { return nil }
        return Value(type: type, size: size, payload: Array(response[48..<(48 + Int(size))]))
    }

    static func readValue(key: UInt32, exchange: Exchange) -> Double? {
        guard let value = read(key: key, exchange: exchange) else { return nil }
        return decode(value)
    }

    static func decode(_ data: Value, integerEncoding: IntegerEncoding = .bigEndian) -> Double? {
        let bytes = data.payload
        guard bytes.count == Int(data.size) else { return nil }
        let value: Double
        switch (data.type, data.size) {
        case (0x666c7420, 4): // flt : LE IEEE Float32
            value = Double(Float(bitPattern: littleEndianUInt32(bytes, at: 0)))
        case (0x66706532, 2): // fpe2: BE unsigned fixed point
            value = Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case (0x73703738, 2): // sp78: BE signed fixed point
            value = Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case (0x75693820, 1): // ui8
            value = Double(bytes[0])
        case (0x75693136, 2), (0x73693136, 2): // ui16 / si16
            let raw: UInt16
            let divisor: Double
            switch integerEncoding {
            case .bigEndian:
                raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
                divisor = 1
            case .batteryLittleEndianMilliUnits:
                raw = UInt16(bytes[0]) | UInt16(bytes[1]) << 8
                divisor = 1_000
            }
            value = (data.type == 0x73693136 ? Double(Int16(bitPattern: raw)) : Double(raw)) / divisor
        default:
            return nil
        }
        return value.isFinite ? value : nil
    }

    private static func littleEndianUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << ($1 * 8) }
    }
}
