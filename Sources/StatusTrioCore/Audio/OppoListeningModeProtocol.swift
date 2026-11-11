import Foundation

/// The OPO v1 application framing an OPPO / OnePlus / realme earbud speaks over
/// its vendor SPP channel.
///
/// Wire format (little-endian, no checksum, no encryption):
///
///     AA | LEN(varint, 7-bit LE) | 00 00 | CMD(u16 LE) | SEQ | PLEN(u16 LE) | payload
///
/// `LEN` covers the two-byte link header plus the whole inner packet, and
/// excludes `AA` and the varint itself. A response carries `CMD | 0x8000` and
/// echoes the request's `SEQ`; its `payload[0]` is a status where `0` means
/// success.
///
/// This is a different family from the Redmi `FE DC BA … EF` frame — no
/// terminator, a varint length, and a low-endian command word — so the Redmi
/// codec cannot be reused. What does carry over is the decoder's job: RFCOMM is
/// a byte stream, so frames arrive fragmented, coalesced, or preceded by noise.
struct OppoFrame: Equatable, Sendable {
    /// The SOF byte every frame starts with.
    static let sync: UInt8 = 0xAA
    /// The bit a response sets on the request's command word.
    static let responseBit: UInt16 = 0x8000
    /// The two link-header bytes between the length and the command word.
    static let linkHeader: [UInt8] = [0x00, 0x00]
    /// `CMD(2) + SEQ(1) + PLEN(2)`.
    static let innerOverhead = 5
    /// `LINK(2) + innerOverhead`.
    static let minimumLength = 2 + innerOverhead

    var command: UInt16
    var sequence: UInt8
    var payload: [UInt8]

    init(command: UInt16, sequence: UInt8, payload: [UInt8] = []) {
        self.command = command
        self.sequence = sequence
        self.payload = payload
    }

    var isResponse: Bool { command & Self.responseBit != 0 }

    /// The command word a response to this frame must carry.
    var responseCommand: UInt16 { command | Self.responseBit }

    var bytes: [UInt8] {
        let length = 2 + Self.innerOverhead + payload.count
        return [Self.sync]
            + Self.encodeVarint(length)
            + Self.linkHeader
            + [UInt8(truncatingIfNeeded: command), UInt8(truncatingIfNeeded: command >> 8)]
            + [sequence]
            + [UInt8(truncatingIfNeeded: payload.count), UInt8(truncatingIfNeeded: payload.count >> 8)]
            + payload
    }

    /// 7-bit little-endian varint: continuation flag in bit 7 of every byte.
    static func encodeVarint(_ value: Int) -> [UInt8] {
        var remaining = max(0, value)
        var out: [UInt8] = []
        while true {
            var byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining > 0 { byte |= 0x80 }
            out.append(byte)
            if remaining == 0 { return out }
        }
    }

    /// Reads a varint, returning `nil` while the bytes are still incomplete and
    /// `.failure` when the encoding is too long to be plausible (so the decoder
    /// can resynchronise instead of buffering forever).
    enum VarintResult: Equatable {
        case value(Int)
        case incomplete
        case invalid
    }

    static func decodeVarint(_ bytes: ArraySlice<UInt8>) -> (result: VarintResult, consumed: Int) {
        var value = 0
        var consumed = 0
        for byte in bytes.prefix(3) {
            value |= Int(byte & 0x7F) << (7 * consumed)
            consumed += 1
            if byte & 0x80 == 0 { return (.value(value), consumed) }
        }
        return (bytes.count >= 3 ? .invalid : .incomplete, consumed)
    }
}

/// Decodes a byte stream into `OppoFrame`s.
///
/// A frame is only emitted once all of its bytes are buffered, and every
/// consistency check that can be made from the frame itself — the link-header
/// padding and the `PLEN`/`LEN` agreement — is made before emitting, so a stray
/// `0xAA` inside a payload cannot swallow the next real frame. Any check that
/// fails drops one byte and resynchronises.
struct OppoFrameDecoder: Sendable {
    private var buffer: [UInt8] = []
    /// A frame is too large to be a control payload; such a length is treated as
    /// a mis-parse rather than buffered indefinitely.
    private let maximumLength = 1024

    init() {}

    mutating func append(_ bytes: [UInt8]) -> [OppoFrame] {
        buffer += bytes
        var frames: [OppoFrame] = []

        while true {
            guard let syncIndex = buffer.firstIndex(of: OppoFrame.sync) else {
                buffer.removeAll()
                return frames
            }
            if syncIndex > 0 { buffer.removeFirst(syncIndex) }

            let afterSync = buffer.dropFirst()
            let (varint, varintCount) = OppoFrame.decodeVarint(afterSync)
            guard case .value(let length) = varint,
                  length >= OppoFrame.minimumLength,
                  length <= maximumLength else {
                // An unfinished varint needs more bytes; anything else is a false
                // sync and the decoder moves on by one byte.
                if case .incomplete = varint { return frames }
                buffer.removeFirst()
                continue
            }

            let headerCount = 1 + varintCount
            let total = headerCount + length
            guard buffer.count >= total else {
                // Not enough bytes — but a stray `0xAA` inside noise yields the same
                // shape, and waiting on it would swallow the frame that follows. If a
                // later sync byte already forms a complete, self-consistent frame,
                // this candidate is noise: drop one byte and resynchronise.
                if hasCompleteFrame(after: 0) {
                    buffer.removeFirst()
                    continue
                }
                return frames
            }

            let commandOffset = headerCount + OppoFrame.linkHeader.count
            guard buffer[headerCount] == OppoFrame.linkHeader[0],
                  buffer[headerCount + 1] == OppoFrame.linkHeader[1] else {
                buffer.removeFirst()
                continue
            }
            let declaredPayload = Int(buffer[commandOffset + 3])
                | Int(buffer[commandOffset + 4]) << 8
            guard declaredPayload == length - OppoFrame.minimumLength else {
                buffer.removeFirst()
                continue
            }

            frames.append(OppoFrame(
                command: UInt16(buffer[commandOffset]) | UInt16(buffer[commandOffset + 1]) << 8,
                sequence: buffer[commandOffset + 2],
                payload: Array(buffer[(commandOffset + 5)..<total])
            ))
            buffer.removeFirst(total)
        }
    }

    /// Whether any byte after `offset` starts a frame that is fully buffered and
    /// passes every check the decoder makes. Used only to reject a false sync.
    private func hasCompleteFrame(after offset: Int) -> Bool {
        guard buffer.count > offset + 3 else { return false }
        for index in (offset + 1)..<buffer.count where buffer[index] == OppoFrame.sync {
            let (varint, varintCount) = OppoFrame.decodeVarint(buffer[(index + 1)...])
            guard case .value(let length) = varint,
                  length >= OppoFrame.minimumLength,
                  length <= maximumLength else { continue }
            let header = index + 1 + varintCount
            let total = header + length
            guard buffer.count >= total else { continue }
            guard buffer[header] == OppoFrame.linkHeader[0],
                  buffer[header + 1] == OppoFrame.linkHeader[1] else { continue }
            let commandOffset = header + OppoFrame.linkHeader.count
            let declaredPayload = Int(buffer[commandOffset + 3]) | Int(buffer[commandOffset + 4]) << 8
            if declaredPayload == length - OppoFrame.minimumLength { return true }
        }
        return false
    }
}

/// The command words this feature drives.
///
/// The upper byte is the command class (`0x01` query, `0x04` write, `0x05` push)
/// and the lower byte is the feature space (`0x00` handshake, `0x03` product ID,
/// `0x0C` noise control, `0x04` noise-control write).
enum OppoCommand {
    static let handshake: UInt16 = 0x0100
    static let productID: UInt16 = 0x0103
    static let eventsQuery: UInt16 = 0x0200
    static let eventsSubscribe: UInt16 = 0x0205
    static let noiseQuery: UInt16 = 0x010C
    static let noiseSet: UInt16 = 0x0404

    /// The acknowledgements, spelled out rather than derived: they are what the
    /// `receive` switch matches on, and a constant case pattern keeps that switch
    /// exhaustive-looking to a reader.
    static let handshakeResponse: UInt16 = 0x8100
    static let productIDResponse: UInt16 = 0x8103
    static let noiseQueryResponse: UInt16 = 0x810C
    static let noiseSetResponse: UInt16 = 0x8404

    /// The `0x010C` sub-type that reports the mode the buds are in right now.
    static let noiseCurrentSubtype: UInt8 = 1
    /// The sub-type that reports which indices the stem's long-press cycles
    /// through — the device stating which modes it is willing to switch between.
    static let noiseCycleSubtype: UInt8 = 2
    /// The sub-type that reports the supported set; some models answer all zero
    /// to say they do not use it.
    static let noiseSupportSubtype: UInt8 = 3

    /// The push event that carries a noise-state change.
    static let noiseEvent: UInt8 = 0x03
}

/// One OPPO-family noise mode, in the app's own vocabulary.
///
/// The wire value is a per-model `protocolIndex`, so it deliberately does not
/// live here: `OppoNoiseProfile` owns the index table, and the view layer keeps
/// talking about "Noise Cancellation".
enum OppoNoiseMode: String, CaseIterable, Equatable, Sendable {
    case off
    case cancellation
    case transparency
}

/// A model's `protocolIndex` table, plus the mapping back from what the buds
/// report to a mode the UI can highlight.
///
/// The tables are per model — the protocol document's X4 measurements show a
/// flat top level (`0` off, `1` cancellation, `2` transparency) with depth
/// sub-indices underneath (`4`…`7`), and states that the buds **always report the
/// sub-index**, which is why `aliases` exists at all.
struct OppoNoiseProfile: Equatable, Sendable {
    /// The product ID this profile was measured on, or `nil` for the generic
    /// fallback that is only selected when the device declares its own cycle.
    let productID: UInt32?
    /// The index written for each mode the capsules offer.
    let indices: [OppoNoiseMode: UInt8]
    /// Indices the device may report that mean one of the modes above.
    let aliases: [UInt8: OppoNoiseMode]
    /// Whether this profile came from a measured table or from the generic
    /// fallback. Reported so a debug log can tell the two apart.
    let isMeasured: Bool

    /// The indices the capsules are drawn for, top level first.
    var selectableModes: [BluetoothListeningMode] {
        var modes: [BluetoothListeningMode] = []
        if indices[.cancellation] != nil { modes.append(.noiseCancellation) }
        if indices[.transparency] != nil { modes.append(.transparency) }
        if indices[.off] != nil { modes.append(.off) }
        return modes
    }

    /// Resolves a reported index to a mode, following the alias table first so
    /// a sub-index (say `7`, "smart cancellation") still highlights the parent.
    func mode(reportedIndex: UInt8) -> BluetoothListeningMode? {
        let mode = aliases[reportedIndex] ?? OppoNoiseMode.allCases.first { indices[$0] == reportedIndex }
        switch mode {
        case .off: return .off
        case .cancellation: return .noiseCancellation
        case .transparency: return .transparency
        case nil: return nil
        }
    }

    /// The index to write for a capsule, or `nil` for a mode this profile cannot
    /// express (`.adaptive`).
    func index(for mode: BluetoothListeningMode) -> UInt8? {
        switch mode {
        case .off: return indices[.off]
        case .noiseCancellation: return indices[.cancellation]
        case .transparency: return indices[.transparency]
        case .adaptive: return nil
        }
    }

    /// The `0x0404` write payload: `[01][01][mask…]`, where the mask is the
    /// single bit for the target index, little-endian and minimal.
    func setPayload(for mode: BluetoothListeningMode) -> [UInt8]? {
        guard let index = index(for: mode) else { return nil }
        let mask = UInt16(1) << UInt16(index)
        var bytes: [UInt8] = [UInt8(truncatingIfNeeded: mask)]
        if mask > 0xFF { bytes.append(UInt8(truncatingIfNeeded: mask >> 8)) }
        return [0x01, 0x01] + bytes
    }
}

/// Resolves the profile to use for a device from what the device itself says.
///
/// The gate is deliberately narrow: a product ID with a measured table wins, and
/// otherwise the device must declare — through its long-press cycle bitmap — that
/// it switches between noise cancellation and transparency. A model that does not
/// answer, answers all zero, or answers a cycle this build does not recognise
/// gets **no profile**, and the transport then fails closed and the capsules never
/// appear. Guessing from the product ID alone would risk writing an index that
/// means "mild cancellation" on one model and "adaptive" on another.
enum OppoNoiseProfiles {
    /// Measured tables, keyed by product ID. Empty until a model is measured on
    /// real hardware; `probe` on a connected pair reports the ID to add here.
    static let measured: [UInt32: OppoNoiseProfile] = [:]

    /// The fallback for a device that declares an ANC + transparency cycle.
    ///
    /// Top-level indices follow the documented flat layout. `off` is offered even
    /// when the cycle omits it, because every model in the reference material has
    /// a top-level off at `0`; if a model does not, the write's read-back will not
    /// match and the UI rolls back rather than showing a false success.
    static let generic = OppoNoiseProfile(
        productID: nil,
        indices: [.off: 0, .cancellation: 1, .transparency: 2],
        aliases: [
            3: .off,
            4: .cancellation, 5: .cancellation, 6: .cancellation, 7: .cancellation,
            8: .transparency,
        ],
        isMeasured: false
    )

    /// The bits the cycle mask must carry for the generic profile to apply:
    /// index `1` (cancellation) and index `2` (transparency).
    static let requiredCycleBits: UInt16 = (1 << 1) | (1 << 2)

    static func profile(productID: UInt32?, cycleMask: UInt16?) -> OppoNoiseProfile? {
        if let productID, let measured = measured[productID] { return measured }
        guard let cycleMask, cycleMask & requiredCycleBits == requiredCycleBits else { return nil }
        return generic
    }
}

/// What the session has confirmed about a device: its mode, and the profile the
/// mode was resolved against.
struct OppoNoiseState: Equatable, Sendable {
    let listeningMode: BluetoothListeningMode

    /// The modes a resolved OPPO device offers. `off` is a drawn capsule, as it
    /// is for the HUAWEI and Redmi families.
    static let selectableListeningModes: [BluetoothListeningMode] = [
        .noiseCancellation, .transparency, .off
    ]
}

/// The OPPO session state machine.
///
/// Holds the sequence counter and walks the exchange in the order the reference
/// implementation verified on hardware: handshake (`0x0100`) to learn the
/// capability bitmap, product ID (`0x0103`), the long-press cycle (`0x010C` subtype
/// `2`) that decides whether this model can be driven at all, then the event
/// subscription and the first state read. Feed decoded frames to `receive`; it
/// returns the frames to send next.
///
/// Every step degrades rather than throws: a device that answers the handshake but
/// never names its cycle simply ends with no profile, which the session reports as
/// "unsupported model" and the panel draws nothing for.
struct OppoSessionEngine: Sendable {
    private(set) var sequence: UInt8 = 0
    private(set) var handshaken = false
    private(set) var productID: UInt32?
    private(set) var profile: OppoNoiseProfile?
    private(set) var cycleMask: UInt16?
    private(set) var supportMask: UInt16?
    private(set) var subscribed = false
    private(set) var currentMode: BluetoothListeningMode?

    /// The last index the device reported, kept until a profile resolves it.
    private var reportedIndex: UInt8?

    mutating func request(_ command: UInt16, _ payload: [UInt8] = []) -> OppoFrame {
        defer { sequence &+= 1 }
        return OppoFrame(command: command, sequence: sequence, payload: payload)
    }

    mutating func handshake() -> OppoFrame {
        request(OppoCommand.handshake, [0x01])
    }

    mutating func requestProductID() -> OppoFrame {
        request(OppoCommand.productID, [0x01])
    }

    mutating func subscribeEvents() -> OppoFrame {
        subscribed = true
        return request(OppoCommand.eventsSubscribe, [0x01, OppoCommand.noiseEvent])
    }

    mutating func queryMode() -> OppoFrame {
        request(OppoCommand.noiseQuery, [OppoCommand.noiseCurrentSubtype, 0x01])
    }

    mutating func queryCycle() -> OppoFrame {
        request(OppoCommand.noiseQuery, [OppoCommand.noiseCycleSubtype, 0x01])
    }

    /// Adopts a profile without walking the handshake. Used for a measured model
    /// table that is known ahead of the exchange, and by the index-table tests.
    mutating func adoptProfile(_ profile: OppoNoiseProfile) {
        self.profile = profile
        if let reportedIndex { currentMode = profile.mode(reportedIndex: reportedIndex) }
    }

    /// The frame that switches to `mode`, or `nil` when this profile cannot
    /// express it — the caller reports that as a mode the device does not have.
    mutating func setMode(_ mode: BluetoothListeningMode) -> OppoFrame? {
        guard let payload = profile?.setPayload(for: mode) else { return nil }
        return request(OppoCommand.noiseSet, payload)
    }

    /// Feeds one received frame and returns the frames to send in response.
    mutating func receive(_ frame: OppoFrame) -> [OppoFrame] {
        if !frame.isResponse {
            return receivePush(frame)
        }
        switch frame.command {
        case OppoCommand.handshakeResponse:
            guard frame.payload.first == 0 else { return [] }
            handshaken = true
            return [requestProductID(), queryCycle()]

        case OppoCommand.productIDResponse:
            if let id = OppoPayload.productID(frame.payload) {
                productID = id
                resolveProfileIfPossible()
            }
            return []

        case OppoCommand.noiseQueryResponse:
            return receiveNoiseAnswer(frame)

        case OppoCommand.noiseSetResponse:
            guard frame.payload.first == 0 else { return [] }
            // The ack only says the control surface accepted the write; the mode
            // is only trusted once the device reports it back.
            return [queryMode()]

        default:
            return []
        }
    }

    private mutating func receiveNoiseAnswer(_ frame: OppoFrame) -> [OppoFrame] {
        guard frame.payload.count >= 2 else { return [] }
        switch frame.payload[1] {
        case OppoCommand.noiseCurrentSubtype:
            guard let mask = OppoPayload.noiseMask(frame.payload, expecting: OppoCommand.noiseCurrentSubtype),
                  let index = OppoPayload.modeIndex(fromMask: mask) else {
                return []
            }
            reportedIndex = index
            currentMode = profile?.mode(reportedIndex: index)
            return []

        case OppoCommand.noiseCycleSubtype:
            guard let mask = OppoPayload.noiseMask(frame.payload, expecting: OppoCommand.noiseCycleSubtype) else {
                return []
            }
            cycleMask = mask
            return resolveProfileIfPossible() ? [subscribeEvents(), queryMode()] : []

        case OppoCommand.noiseSupportSubtype:
            guard let mask = OppoPayload.noiseMask(frame.payload, expecting: OppoCommand.noiseSupportSubtype) else {
                return []
            }
            supportMask = mask
            // Only a fallback: models that answer all zero here (as the measured
            // X4 does) rely on the cycle sub-type instead.
            if resolveProfileIfPossible(), !subscribed { return [subscribeEvents(), queryMode()] }
            return []

        default:
            return []
        }
    }

    /// Resolves the profile once both the product ID and a mode mask are known,
    /// then re-reads any index that arrived before the profile existed.
    @discardableResult
    private mutating func resolveProfileIfPossible() -> Bool {
        guard profile == nil else { return false }
        guard let resolved = OppoNoiseProfiles.profile(productID: productID, cycleMask: cycleMask ?? supportMask) else {
            return false
        }
        profile = resolved
        if let reportedIndex { currentMode = resolved.mode(reportedIndex: reportedIndex) }
        return true
    }

    /// A device push. The subscribe call is what makes the buds report stem and
    /// phone changes without waiting for our next read.
    ///
    /// The documented shape is `03 01 01 <mask…>`: the event id, then two bytes
    /// the reference material does not name, then the same mode mask a `0x010C`
    /// answer carries. Rather than hard-code that guess, the mask is taken as the
    /// first bytes after the event id (with the `01 01` pair dropped when present)
    /// and only accepted when it names exactly one mode — anything else is
    /// ignored, so a firmware that shapes its pushes differently loses live
    /// updates but never invents a mode.
    private mutating func receivePush(_ frame: OppoFrame) -> [OppoFrame] {
        guard frame.command & 0xFF00 == 0x0200 || frame.command & 0xFF00 == 0x0500 else {
            return []
        }
        guard frame.payload.first == OppoCommand.noiseEvent else { return [] }

        var tail = Array(frame.payload.dropFirst())
        if tail.count >= 2, tail[0] == 0x01, tail[1] == 0x01 {
            tail.removeFirst(2)
        }
        var mask: UInt16 = 0
        for (offset, byte) in tail.prefix(2).enumerated() {
            mask |= UInt16(byte) << (8 * UInt32(offset))
        }
        guard let index = OppoPayload.modeIndex(fromMask: mask) else { return [] }
        reportedIndex = index
        currentMode = profile?.mode(reportedIndex: index)
        return []
    }
}

/// Decodes the payloads this feature reads. Every parser returns `nil` rather
/// than throwing: an unrecognised payload is normal (a model answering a
/// sub-type it does not implement), not an exception.
enum OppoPayload {
    /// `[status][pid LE, up to 3 bytes]`; `status` must be `0`.
    static func productID(_ payload: [UInt8]) -> UInt32? {
        guard payload.count >= 2, payload[0] == 0 else { return nil }
        var value: UInt32 = 0
        for (offset, byte) in payload.dropFirst().prefix(3).enumerated() {
            value |= UInt32(byte) << (8 * UInt32(offset))
        }
        return value == 0 ? nil : value
    }

    /// `[status][subtype][type][mask LE…]` → the mask, or `nil` when the status
    /// is non-zero or the payload is short.
    static func noiseMask(_ payload: [UInt8], expecting subtype: UInt8) -> UInt16? {
        guard payload.count >= 4, payload[0] == 0, payload[1] == subtype else { return nil }
        var mask: UInt16 = 0
        for (offset, byte) in payload.dropFirst(3).prefix(2).enumerated() {
            mask |= UInt16(byte) << (8 * UInt32(offset))
        }
        return mask
    }

    /// The mode bit a `0x010C` current-mode answer carries: exactly one bit set.
    static func modeIndex(fromMask mask: UInt16) -> UInt8? {
        guard mask != 0 else { return nil }
        // A mask with several bits set does not name one mode; fail closed.
        guard mask & (mask &- 1) == 0 else { return nil }
        var index: UInt8 = 0
        while index < 16 {
            if mask & (UInt16(1) << UInt16(index)) != 0 { return index }
            index += 1
        }
        return nil
    }
}
