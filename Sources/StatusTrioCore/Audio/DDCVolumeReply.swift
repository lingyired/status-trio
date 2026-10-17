import Foundation

/// Structured verdict for one 11-byte Get VCP reply buffer.
///
/// The previous code collapsed every rejection into "nil", so a real device
/// failure could only be reported as a generic read failure. Naming the shape
/// lets the diagnostic log say whether the bus never answered, the monitor
/// refused, or the bytes arrived garbled.
enum DDCVolumeReplyKind: Equatable, Sendable {
    case valid(DDCVolumeReply)
    /// Buffer came back all zero: a write was accepted but nothing filled it.
    case zeros
    /// Buffer is still `0xFF` everywhere: the read never landed in the mapping.
    case untouched
    case wrongLength
    /// Header bytes are not a Get VCP Feature reply (`6E 88 02`).
    case wrongHeader
    /// Reply echoed a different VCP than the one requested.
    case wrongVCP
    /// The display explicitly refused VCP 0x62 (result code 1).
    case vcpRefused
    case badChecksum
    /// Reply parsed but the reported range is impossible.
    case invalidRange

    /// Identifier-free label for diagnostics.
    var diagnosticName: String {
        switch self {
        case .valid: "valid"
        case .zeros: "zeros"
        case .untouched: "untouched"
        case .wrongLength: "wrongLength"
        case .wrongHeader: "wrongHeader"
        case .wrongVCP: "wrongVCP"
        case .vcpRefused: "vcpRefused"
        case .badChecksum: "badChecksum"
        case .invalidRange: "invalidRange"
        }
    }
}

struct DDCVolumeReply: Equatable, Sendable {
    let current: UInt16
    let maximum: UInt16

    var scalar: Double {
        Double(current) / Double(maximum)
    }

    /// Classifies a raw reply buffer without accepting anything questionable.
    static func classify(_ bytes: [UInt8]) -> DDCVolumeReplyKind {
        guard bytes.count == 11 else {
            if !bytes.isEmpty, bytes.allSatisfy({ $0 == 0xFF }) { return .untouched }
            if !bytes.isEmpty, bytes.allSatisfy({ $0 == 0 }) { return .zeros }
            return .wrongLength
        }
        if bytes.allSatisfy({ $0 == 0 }) { return .zeros }
        if bytes.allSatisfy({ $0 == 0xFF }) { return .untouched }
        guard bytes[0] == 0x6E, bytes[1] == 0x88, bytes[2] == 0x02 else { return .wrongHeader }
        if bytes[3] == 0x01 { return .vcpRefused }
        guard bytes[3] == 0 else { return .wrongHeader }
        guard bytes[4] == 0x62 else { return .wrongVCP }
        guard bytes.prefix(10).reduce(UInt8(0x50), ^) == bytes[10] else { return .badChecksum }

        let maximum = UInt16(bytes[6]) << 8 | UInt16(bytes[7])
        let current = UInt16(bytes[8]) << 8 | UInt16(bytes[9])
        guard maximum > 0, current <= maximum else { return .invalidRange }
        return .valid(Self(current: current, maximum: maximum))
    }

    static func decode(_ bytes: [UInt8]) -> Self? {
        guard case .valid(let reply) = classify(bytes) else { return nil }
        return reply
    }

    func targetValue(for scalar: Double) -> UInt16 {
        guard scalar.isFinite else { return current }
        return UInt16((min(1, max(0, scalar)) * Double(maximum)).rounded())
    }
}
