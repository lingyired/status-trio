import Foundation

/// Which checksum seed the Get VCP request uses.
///
/// DDC/CI request checksums start from the host address shifted left
/// (`0x37 << 1 == 0x6E`). Implementations disagree about also folding in the
/// data address `0x51`:
///
/// - `.standard` folds it in and produces `82 01 62 DE` (MonitorControl,
///   Candela, OpenDisplay, FreeDisplay claim this).
/// - `.legacy` omits it and produces `82 01 62 8F`, which is what Status Trio
///   shipped and what the Acer XV272U responded to.
///
/// The mode is explicit so a protocol choice is never hidden behind a bare
/// boolean at a call site.
enum DDCGetVCPChecksumMode: Equatable, Sendable {
    case standard
    case legacy

    /// Whether the data address `0x51` participates in the checksum seed.
    var includesDataAddress: Bool {
        switch self {
        case .standard: true
        case .legacy: false
        }
    }
}

/// One bounded, read-only Get VCP attempt configuration.
///
/// The third argument of `IOAVServiceReadI2C` is a validated compatibility
/// axis: MonitorControl and Candela pass `0`, OpenDisplay and FreeDisplay pass
/// `0x51`. Neither value is assumed correct; both are tried in order.
struct DDCReadProfile: Equatable, Sendable {
    /// Stable label used in tests and diagnostics ("P1"..."P4").
    let label: String
    let checksumMode: DDCGetVCPChecksumMode
    /// `dataAddress` argument passed to `IOAVServiceReadI2C`.
    let readAddress: UInt32

    /// The bounded probe order. Cheapest/most common first.
    static let candidates: [DDCReadProfile] = [
        DDCReadProfile(label: "P1", checksumMode: .standard, readAddress: 0x51),
        DDCReadProfile(label: "P2", checksumMode: .standard, readAddress: 0x00),
        DDCReadProfile(label: "P3", checksumMode: .legacy, readAddress: 0x51),
        DDCReadProfile(label: "P4", checksumMode: .legacy, readAddress: 0x00)
    ]
}

/// DDC/CI packet construction, kept pure so the exact bytes are unit-testable
/// without IOKit.
enum DDCPacket {
    static let chipAddress: UInt32 = 0x37
    static let dataAddress: UInt32 = 0x51
    static let volumeVCP: UInt8 = 0x62

    /// Get VCP Feature request. Body is always `82 01 <vcp>`; only the
    /// trailing checksum changes with the mode.
    static func getVCPRequest(vcp: UInt8 = volumeVCP, checksumMode: DDCGetVCPChecksumMode) -> [UInt8] {
        let body: [UInt8] = [0x80 | (1 + 1), 0x01, vcp]
        return body + [checksum(body, includeDataAddress: checksumMode.includesDataAddress)]
    }

    /// Set VCP Feature request. Unchanged from the previously verified format.
    static func setVCPRequest(vcp: UInt8 = volumeVCP, value: UInt16) -> [UInt8] {
        let body: [UInt8] = [0x80 | (3 + 1), 0x03, vcp, UInt8(value >> 8), UInt8(value & 0xff)]
        return body + [checksum(body, includeDataAddress: true)]
    }

    static func checksum(_ payload: [UInt8], includeDataAddress: Bool) -> UInt8 {
        let seed = UInt8(chipAddress << 1) ^ (includeDataAddress ? UInt8(dataAddress) : 0)
        return payload.reduce(seed, ^)
    }
}

/// Result of a single bounded read attempt against one profile.
enum DDCProbeOutcome: Equatable, Sendable {
    case reply(DDCVolumeReplyKind)
    /// The Get VCP request write never returned `kIOReturnSuccess`.
    case requestWriteFailed
    /// The reply read never returned `kIOReturnSuccess`.
    case replyReadFailed

    var diagnosticName: String {
        switch self {
        case .reply(let kind): kind.diagnosticName
        case .requestWriteFailed: "requestWriteFailed"
        case .replyReadFailed: "replyReadFailed"
        }
    }

    /// Which stage of the exchange produced this outcome.
    var diagnosticStage: String {
        switch self {
        case .reply: "validate"
        case .requestWriteFailed: "requestWrite"
        case .replyReadFailed: "replyRead"
        }
    }
}

struct DDCProbeAttempt: Equatable, Sendable {
    let profile: DDCReadProfile
    let outcome: DDCProbeOutcome
}

struct DDCProbeSelection: Equatable, Sendable {
    /// The profile that answered with a fully validated reply, or nil.
    let profile: DDCReadProfile?
    /// The validated reply that selected `profile`.
    let reply: DDCVolumeReply?
    /// A fully validated frame refused VCP 0x62 (result code 1). Further
    /// candidates are pointless: the monitor understood the request.
    ///
    /// Only `DDCVolumeReply.classify` may set this, and it only returns
    /// `.vcpRefused` for a frame whose length, header, echoed VCP and checksum
    /// all pass, so a stray `01` byte in a stale frame cannot end the probe.
    let refused: Bool
    let attempts: [DDCProbeAttempt]

    /// The stage-tagged reason no profile was selected, or nil when one was.
    /// Diagnostics report this instead of a catch-all "unsupported VCP".
    var failure: DDCReadFailure? {
        guard profile == nil else { return nil }
        if refused { return .vcpRejected }
        guard let last = attempts.last else { return .replyReadFailed }
        switch last.outcome {
        case .reply(let kind): return .replyRejected(kind)
        case .requestWriteFailed: return .requestWriteFailed
        case .replyReadFailed: return .replyReadFailed
        }
    }
}

/// Bounded, ordered, read-only profile probe for one already-resolved service.
///
/// It never enumerates other targets and never writes: it only calls the
/// injected single-profile reader until one answers with a validated reply.
enum DDCReadProfileProbe {
    static func select(
        candidates: [DDCReadProfile] = DDCReadProfile.candidates,
        using attempt: (DDCReadProfile) -> DDCProbeOutcome
    ) -> DDCProbeSelection {
        var attempts: [DDCProbeAttempt] = []
        for profile in candidates {
            let outcome = attempt(profile)
            attempts.append(DDCProbeAttempt(profile: profile, outcome: outcome))
            switch outcome {
            case .reply(.valid(let reply)):
                return DDCProbeSelection(profile: profile, reply: reply, refused: false, attempts: attempts)
            case .reply(.vcpRefused):
                return DDCProbeSelection(profile: nil, reply: nil, refused: true, attempts: attempts)
            case .reply, .requestWriteFailed, .replyReadFailed:
                continue
            }
        }
        return DDCProbeSelection(profile: nil, reply: nil, refused: false, attempts: attempts)
    }
}

/// Keeps a failed probe from re-running on every poll of the same service.
enum DDCReadProfilePolicy {
    /// At most one full probe per this many reads of the same service. The
    /// coordinator's failure backoff stretches the poll interval, so a service
    /// that never answers is retried infrequently rather than every cycle.
    /// A fresh service (topology change, output switch, sleep/wake) starts over.
    static let readsBetweenProbes = 6

    static func shouldRunProbe(cachedProfile: DDCReadProfile?, readsSinceLastProbe: Int) -> Bool {
        guard cachedProfile == nil else { return false }
        return readsSinceLastProbe >= readsBetweenProbes
    }
}
