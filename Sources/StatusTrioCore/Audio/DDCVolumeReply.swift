import Foundation

/// Where a read failed. The stage is part of the value so a diagnostic line can
/// name the layer (resolve, request write, reply read, validation) instead of
/// collapsing every failure into one "unsupported" label.
enum DDCReadFailure: Equatable, Sendable {
    /// No DDC service could be opened for the current output.
    case serviceUnavailable
    /// The Get VCP request write never returned `kIOReturnSuccess`.
    case requestWriteFailed
    /// The reply read never returned `kIOReturnSuccess`. This also covers a read
    /// that returned success without filling the buffer: `IOAVServiceReadI2C`
    /// reporting success is not proof that a frame arrived.
    case replyReadFailed
    /// Frames arrived but none passed validation; carries the last rejection.
    case replyRejected(DDCVolumeReplyKind)
    /// A complete, checksum-valid frame refused VCP 0x62.
    case vcpRejected
    /// The read never completed inside the coordinator's watchdog window.
    case timeout

    /// Stable, identifier-free label for diagnostics.
    var diagnosticName: String {
        switch self {
        case .serviceUnavailable: "serviceUnavailable"
        case .requestWriteFailed: "requestWriteFailed"
        case .replyReadFailed: "replyReadFailed"
        case .replyRejected(let kind): "replyRejected(\(kind.diagnosticName))"
        case .vcpRejected: "vcpRejected"
        case .timeout: "timeout"
        }
    }

    /// The stage tag logged next to this failure.
    var diagnosticStage: String {
        switch self {
        case .serviceUnavailable: "resolve"
        case .requestWriteFailed: "requestWrite"
        case .replyReadFailed, .timeout: "replyRead"
        case .replyRejected, .vcpRejected: "validate"
        }
    }
}

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
    /// A complete, checksum-valid frame reported a non-zero result code that is
    /// not "unsupported VCP". The code is display-specific, so this is never
    /// treated as protocol support evidence.
    case displayReportedError(UInt8)
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
        case .displayReportedError: "displayReportedError"
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
    ///
    /// The order matters. A result code is only meaningful once the frame is
    /// known to answer *this* request: length, then the reply header, then the
    /// echoed VCP, then the checksum. Checking the result code first let a
    /// stale or garbled frame with a stray `01` byte report a refusal the
    /// display never made, which aborted the P1-P4 compatibility probe.
    static func classify(_ bytes: [UInt8]) -> DDCVolumeReplyKind {
        guard bytes.count == 11 else {
            if !bytes.isEmpty, bytes.allSatisfy({ $0 == 0xFF }) { return .untouched }
            if !bytes.isEmpty, bytes.allSatisfy({ $0 == 0 }) { return .zeros }
            return .wrongLength
        }
        if bytes.allSatisfy({ $0 == 0 }) { return .zeros }
        if bytes.allSatisfy({ $0 == 0xFF }) { return .untouched }
        guard bytes[0] == 0x6E, bytes[1] == 0x88, bytes[2] == 0x02 else { return .wrongHeader }
        guard bytes[4] == 0x62 else { return .wrongVCP }
        guard bytes.prefix(10).reduce(UInt8(0x50), ^) == bytes[10] else { return .badChecksum }
        switch bytes[3] {
        case 0: break
        case 1: return .vcpRefused
        default: return .displayReportedError(bytes[3])
        }

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

/// A read either produced a validated reply or a stage-tagged failure. A bare
/// `nil` could not say which, and every failure had to be reported as if the
/// display simply did not support VCP 0x62.
enum DDCVolumeReadResult: Equatable, Sendable {
    case reply(DDCVolumeReply)
    case failure(DDCReadFailure)

    var replyValue: DDCVolumeReply? {
        guard case .reply(let reply) = self else { return nil }
        return reply
    }

    var failureReason: DDCReadFailure? {
        guard case .failure(let failure) = self else { return nil }
        return failure
    }
}

/// The outcome of one Set VCP attempt. `acknowledged` means the I2C write
/// returned success, which is not the same as the display accepting the value
/// or the audible volume changing.
enum DDCWriteResult: Equatable, Sendable {
    case acknowledged(value: UInt16)
    case failed(DDCReadFailure)
}

/// What Status Trio currently knows about DDC volume for the selected output.
///
/// `readable` and `writeVerified` are deliberately separate: a readable
/// register proves nothing about the write path, and an acknowledged write
/// proves nothing about the display having applied it.
enum DDCVolumeCapability: Equatable, Sendable {
    /// Nothing is known yet, or the previous knowledge was invalidated
    /// (output switch, sleep/wake, topology change, worker reset).
    case unknown
    case unavailable(DDCReadFailure)
    /// A validated read of the display's current value.
    case readable(DDCVolumeReply)
    /// A Set VCP was acknowledged and the read-back agreed with the requested
    /// register value.
    case writeVerified(DDCVolumeReply)
    /// A Set VCP was acknowledged but the read-back reported something else.
    /// The write reached the display and was not applied as requested.
    case writeUnverified(DDCVolumeReply)

    /// The value that may be shown as the display's current volume. Nil means
    /// "unknown", so no stale percentage may survive a failed read.
    var scalar: Double? {
        switch self {
        case .unknown, .unavailable: nil
        case .readable(let reply), .writeVerified(let reply), .writeUnverified(let reply): reply.scalar
        }
    }

    /// Whether the popover may offer a DDC write for this output.
    var isWritable: Bool { scalar != nil }

    var diagnosticName: String {
        switch self {
        case .unknown: "unknown"
        case .unavailable(let failure): "unavailable(\(failure.diagnosticName))"
        case .readable: "readable"
        case .writeVerified: "writeVerified"
        case .writeUnverified: "writeUnverified"
        }
    }
}
