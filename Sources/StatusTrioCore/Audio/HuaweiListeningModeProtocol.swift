import Foundation

/// The three noise-control modes a HUAWEI FreeBuds-family device exposes over
/// its vendor SPP channel.
///
/// The raw values are the second byte of the `2B 04` write payload and the
/// second byte of the two-byte state `2B 2A` returns. `normal` is the mode the
/// UI calls “off”; there is no dedicated “off” byte.
enum HuaweiNoiseMode: UInt8, Equatable, Sendable {
    case normal = 0
    case cancellation = 1
    case awareness = 2
}

/// One reading of the device's noise-control state.
///
/// The state response carries the level byte first and the mode byte second —
/// the reverse of the write payload. The level is kept raw because its meaning
/// depends on the mode (`cancellation` levels are comfort/normal/ultra/dynamic,
/// `awareness` levels are voice-boost/normal) and this app only switches modes.
struct HuaweiNoiseState: Equatable, Sendable {
    let mode: HuaweiNoiseMode
    let level: UInt8

    /// Builds a state from the two bytes of the `2B 2A` response's parameter 1.
    /// An unknown mode byte fails closed rather than guessing a mode.
    init?(level: UInt8, mode: UInt8) {
        guard let mode = HuaweiNoiseMode(rawValue: mode) else { return nil }
        self.mode = mode
        self.level = level
    }

    /// The mode the shared listening-mode control labels this state with.
    var listeningMode: BluetoothListeningMode {
        switch mode {
        case .normal: return .off
        case .cancellation: return .noiseCancellation
        case .awareness: return .transparency
        }
    }

    /// The modes this app offers for a HUAWEI device. `off` is included — unlike
    /// the AirPods set — because turning noise control off is one of the three
    /// modes the hardware itself cycles through.
    static let selectableListeningModes: [BluetoothListeningMode] = [
        .noiseCancellation, .transparency, .off
    ]

    /// Maps a tapped capsule to a writable mode, or `nil` for a mode this
    /// protocol cannot express (`.adaptive`).
    static func noiseMode(for listeningMode: BluetoothListeningMode) -> HuaweiNoiseMode? {
        switch listeningMode {
        case .off: return .normal
        case .noiseCancellation: return .cancellation
        case .transparency: return .awareness
        case .adaptive: return nil
        }
    }
}

extension HuaweiNoiseMode {
    /// The `2B 04` parameter-1 payload for this mode.
    ///
    /// `0xFF` in the level byte asks the device for its default level for the
    /// mode, which is what OpenFreebuds sends when only the mode changes. A
    /// concrete level would be model-specific: the same number means “ultra” on
    /// a 6i and something else, or nothing at all, on a model without levels.
    var writePayload: [UInt8] {
        self == .normal ? [rawValue, 0x00] : [rawValue, 0xFF]
    }
}

/// One HUAWEI vendor SPP frame.
///
/// Wire format, derived from OpenFreebuds and confirmed against a FreeBuds 6i:
///
///    5A | length(2, big-endian) | 00 | command(2) | [id, size, value]... | CRC16-XMODEM(2)
///
/// `length` is `1 + command.count + parameters.count`; it does **not** include
/// the two CRC bytes. A reader must therefore consume `4 + length + 1` bytes.
/// Reading only `4 + length` leaves one CRC byte behind and desynchronises every
/// subsequent frame.
struct HuaweiSPPFrame: Equatable, Sendable {
    static let magic: UInt8 = 0x5A
    static let readANCCommand: [UInt8] = [0x2B, 0x2A]
    static let writeANCCommand: [UInt8] = [0x2B, 0x04]

    let command: [UInt8]
    let parameters: [UInt8: [UInt8]]

    init(command: [UInt8], parameters: [UInt8: [UInt8]] = [:]) {
        self.command = command
        self.parameters = parameters
    }

    /// Encodes the frame, including the CRC trailer.
    func encoded() -> [UInt8] {
        var body = command
        for id in parameters.keys.sorted() {
            let value = parameters[id] ?? []
            body.append(id)
            body.append(UInt8(truncatingIfNeeded: value.count))
            body.append(contentsOf: value)
        }

        let length = UInt16(body.count + 1)
        var out: [UInt8] = [Self.magic, UInt8(length >> 8), UInt8(length & 0xFF), 0x00]
        out.append(contentsOf: body)
        let crc = Self.crc16(out)
        out.append(UInt8(crc >> 8))
        out.append(UInt8(crc & 0xFF))
        return out
    }

    /// Decodes one complete frame. Returns `nil` for a partial, malformed, or
    /// checksum-mismatched frame so the caller can drop it without acting on it.
    static func decode(_ bytes: [UInt8]) -> HuaweiSPPFrame? {
        guard bytes.count >= 8, bytes[0] == magic, bytes[3] == 0x00 else { return nil }
        let length = Int(bytes[1]) << 8 | Int(bytes[2])
        guard length >= 3, bytes.count == 4 + length + 1 else { return nil }

        let crc = UInt16(bytes[bytes.count - 2]) << 8 | UInt16(bytes[bytes.count - 1])
        guard crc16(Array(bytes[0..<(bytes.count - 2)])) == crc else { return nil }

        let bodyEnd = length + 3
        guard bodyEnd <= bytes.count - 2 else { return nil }
        let command = Array(bytes[4..<6])

        var parameters: [UInt8: [UInt8]] = [:]
        var position = 6
        while position < bodyEnd {
            guard position + 2 <= bodyEnd else { return nil }
            let id = bytes[position]
            let size = Int(bytes[position + 1])
            guard position + 2 + size <= bodyEnd else { return nil }
            parameters[id] = Array(bytes[(position + 2)..<(position + 2 + size)])
            position += 2 + size
        }
        return HuaweiSPPFrame(command: command, parameters: parameters)
    }

    /// CRC-16/XMODEM, the polynomial and initial value HUAWEI's frames use.
    static func crc16(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
        }
        return crc
    }
}

/// Why a HUAWEI SPP operation could not complete.
enum HuaweiListeningModeError: Error, Equatable, Sendable {
    case deviceUnavailable
    case connectionFailed(Int32)
    case sdpFailed(Int32)
    case channelOpenFailed(Int32)
    case notOpen
    case writeFailed(Int32)
    case timeout
    case malformedResponse
    case rejected(UInt8)
}

/// The write/read seam the listening-mode controller drives.
///
/// `setMode` returns the state read back after the write; the controller treats
/// a mismatch as unconfirmed, exactly as the CoreAudio path does.
protocol HuaweiListeningModeTransporting: Sendable {
    func state(address: String) async throws -> HuaweiNoiseState
    func setMode(_ mode: HuaweiNoiseMode, address: String) async throws -> HuaweiNoiseState
    func closeAll()
}
