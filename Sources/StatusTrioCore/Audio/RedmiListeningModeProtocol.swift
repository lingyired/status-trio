import Foundation

/// The three noise-control modes a Redmi / Xiaomi earbuds-family device exposes
/// over its vendor SPP channel.
///
/// The raw values are the third byte of the `08` write payload and the mode byte
/// that the state TLVs report. `off` is the mode the UI calls “关闭”, `cancellation`
/// is “降噪”, and `transparency` is “通透”.
///
/// Adapted from Apechi/XiaomayEarbudsWin (MIT) and the Redmi Buds for Mac
/// reference implementation.
enum RedmiNoiseMode: UInt8, CaseIterable, Equatable, Sendable {
    case off = 0
    case cancellation = 1
    case transparency = 2

    var title: String {
        switch self {
        case .off: return "关闭"
        case .cancellation: return "降噪"
        case .transparency: return "通透"
        }
    }
}

extension RedmiNoiseMode {
    /// The `08` write payload for this mode.
    ///
    /// The reference implementation always sends `[2, 4, mode]`; `2 4` select the
    /// noise-control parameter slot, and the trailing byte is the mode value.
    var writePayload: [UInt8] { [2, 4, rawValue] }
}

/// Maps a shared listening mode to a Redmi mode, or `nil` for a mode this
/// protocol cannot express (`.adaptive`).
func redmiMode(for listeningMode: BluetoothListeningMode) -> RedmiNoiseMode? {
    switch listeningMode {
    case .off: return .off
    case .noiseCancellation: return .cancellation
    case .transparency: return .transparency
    case .adaptive: return nil
    }
}

/// One vendor SPP frame as sent to / received from a Redmi earbuds device.
///
/// Wire format (big-endian length, status only in non-request frames):
///
///    FE DC BA | type(1) | opcode(1) | len(2) | [status(1)] | seq(1) | payload | EF
///
/// `len` covers `payload.count + (isRequest ? 1 : 2)` — i.e. the sequence byte
/// plus the status byte when present. A request has the `0x40` bit set in its
/// type and omits the status byte; a response clears that bit and carries it.
struct RedmiBudsFrame: Equatable, Sendable {
    var type: UInt8 = 0xC4
    var opcode: UInt8
    var sequence: UInt8
    var payload: [UInt8] = []
    var status: UInt8 = 0

    var isRequest: Bool { type & 0x40 != 0 }

    var bytes: [UInt8] {
        let count = payload.count + (isRequest ? 1 : 2)
        return [0xFE, 0xDC, 0xBA, type, opcode, UInt8(count >> 8), UInt8(count & 255)]
            + (isRequest ? [] : [status]) + [sequence] + payload + [0xEF]
    }
}

/// Decodes a byte stream into `RedmiBudsFrame`s.
///
/// RFCOMM is a stream: a frame may arrive fragmented or be coalesced with the
/// next, and a frame header can appear inside another frame's payload. The
/// decoder scans for the `FE DC BA` sync header, validates length and terminator,
/// and only emits a frame once its whole payload is buffered.
struct RedmiBudsFrameDecoder: Sendable {
    private var buffer: [UInt8] = []

    init() {}

    /// Appends bytes and returns any complete frames decoded so far. Incomplete
    /// frames stay buffered for the next call.
    mutating func append(_ bytes: [UInt8]) -> [RedmiBudsFrame] {
        buffer += bytes
        var frames: [RedmiBudsFrame] = []
        while buffer.count >= 3 {
            guard Array(buffer.prefix(3)) == [0xFE, 0xDC, 0xBA] else {
                buffer.removeFirst()
                continue
            }
            guard buffer.count >= 7 else { break }
            let isRequest = buffer[3] & 0x40 != 0
            let overhead = isRequest ? 1 : 2
            let length = Int(buffer[5]) << 8 | Int(buffer[6])
            guard length >= overhead, length <= 4096 else {
                buffer.removeFirst()
                continue
            }
            let total = 8 + length
            guard buffer.count >= total else { break }
            guard buffer[total - 1] == 0xEF else {
                buffer.removeFirst()
                continue
            }
            let offset = isRequest ? 8 : 9
            frames.append(RedmiBudsFrame(
                type: buffer[3],
                opcode: buffer[4],
                sequence: buffer[offset - 1],
                payload: Array(buffer[offset..<(total - 1)]),
                status: isRequest ? 0 : buffer[7]
            ))
            buffer.removeFirst(total)
        }
        return frames
    }
}

/// The decoded state a Redmi device reports: current noise mode and per-ear /
/// case battery percentages.
struct RedmiBudsState: Equatable, Sendable {
    var mode: RedmiNoiseMode?
    private(set) var modeRevision = 0
    var left: UInt8?
    var right: UInt8?
    var caseBattery: UInt8?

    mutating func update(from frame: RedmiBudsFrame) {
        guard frame.status == 0 else { return }
        var i = 0
        let p = frame.payload
        while i < p.count {
            let len = Int(p[i])
            guard len >= 1, i + len < p.count else { break }
            let item = Array(p[(i + 1)...(i + len)])
            switch frame.opcode {
            case 0x02:
                if item[0] == 0x07, item.count >= 4 { updateBattery(Array(item[1...3])) }
            case 0x09:
                if item[0] == 0x09, item.count >= 2 { recordMode(item[1]) }
            case 0x0E:
                if item[0] == 0x00, item.count >= 4 { updateBattery(Array(item[1...3])) }
                if item[0] == 0x04, item.count >= 2 { recordMode(item[1]) }
            case 0xF4:
                if item.count >= 4, item[1] == 0x0B { recordMode(item[2]) }
            default:
                break
            }
            i += len + 1
        }
    }

    private mutating func recordMode(_ value: UInt8) {
        guard let mode = RedmiNoiseMode(rawValue: value) else { return }
        self.mode = mode
        modeRevision += 1
    }

    private mutating func updateBattery(_ values: [UInt8]) {
        func percent(_ v: UInt8) -> UInt8? {
            v == 255 || v & 127 > 100 ? nil : v & 127
        }
        left = percent(values[0])
        right = percent(values[1])
        caseBattery = percent(values[2])
    }
}

/// The Redmi vendor-SPP protocol state machine.
///
/// Owns the sequence counter and walks the multi-step challenge handshake that
/// authenticates the control channel, then tracks mode writes and read-back.
/// Feed decoded frames to `receive`; it returns frames to send in reply.
struct RedmiBudsProtocol: Sendable {
    private var sequence: UInt8 = 0
    private var challengeSequence: UInt8?
    private var confirmSequence: UInt8?
    private(set) var authenticated = false
    private(set) var state = RedmiBudsState()

    mutating func request(_ opcode: UInt8, _ payload: [UInt8]) -> RedmiBudsFrame {
        defer { sequence &+= 1 }
        return RedmiBudsFrame(opcode: opcode, sequence: sequence, payload: payload)
    }

    /// The initial `50` authentication frame carrying a random challenge.
    mutating func begin() -> RedmiBudsFrame {
        let frame = request(0x50, [1] + (0..<16).map { _ in UInt8.random(in: 0...255) })
        challengeSequence = frame.sequence
        return frame
    }

    mutating func setMode(_ mode: RedmiNoiseMode) -> RedmiBudsFrame {
        request(0x08, [2, 4, mode.rawValue])
    }

    mutating func readMode() -> RedmiBudsFrame {
        request(0x09, [255, 255, 255, 255])
    }

    /// Feeds one received frame and returns frames to send in response.
    mutating func receive(_ frame: RedmiBudsFrame) -> [RedmiBudsFrame] {
        func reply(_ payload: [UInt8] = []) -> RedmiBudsFrame {
            RedmiBudsFrame(type: 0x04, opcode: frame.opcode, sequence: frame.sequence, payload: payload)
        }
        if frame.opcode == 0x50 {
            if !authenticated, frame.type == 0x04, frame.status == 0,
               frame.sequence == challengeSequence, confirmSequence == nil {
                let confirm = request(0x51, [1, 0])
                confirmSequence = confirm.sequence
                return [confirm]
            }
            // Real Buds 8 also sends `C4` challenges after our confirmation has
            // completed, and they must be answered with an auth response.
            if frame.isRequest, frame.payload.count == 17, frame.payload.first == 1 {
                return [reply([1] + RedmiBudsAuthentication.response(to: Array(frame.payload.dropFirst())))]
            }
        }
        if frame.opcode == 0x51 {
            if frame.type == 0x04, frame.status == 0, frame.sequence == confirmSequence, !authenticated {
                authenticated = true
                return [reply([1]), request(0x02, [255, 255, 255, 255]), readMode()]
            }
            if frame.type == 0xC0 { return [reply([1])] }
        }
        guard authenticated else { return [] }
        // Never interpret incoming requests as read-back state.
        if [UInt8(0x04), 0xC0, 0xC7].contains(frame.type) { state.update(from: frame) }
        if frame.opcode == 0x0E || frame.opcode == 0xF4 { return [reply()] }
        return []
    }
}

/// The Redmi / Xiaomi earbuds challenge-response authentication, ported from
/// Apechi/XiaomayEarbudsWin `bt/auth.rs` (MIT).
enum RedmiBudsAuthentication {
    static let plaintext: [UInt8] =
        [0x11, 0x22, 0x33, 0x33, 0x22, 0x11, 0x11, 0x22, 0x33, 0x33, 0x22, 0x11, 0x11, 0x22, 0x33, 0x33]
    static let coefficients = [
        [2, 1, 1, 1, 4, 2, 1, 1, 2, 2, 4, 2, 4, 4, 16, 8],
        [2, 1, 1, 1, 4, 2, 1, 1, 1, 1, 2, 1, 2, 2, 8, 4],
        [1, 1, 4, 2, 2, 2, 4, 2, 16, 8, 4, 4, 2, 1, 1, 1],
        [1, 1, 4, 2, 1, 1, 2, 1, 8, 4, 2, 2, 2, 1, 1, 1],
        [16, 8, 2, 2, 4, 2, 4, 4, 1, 1, 4, 2, 1, 1, 2, 1],
        [8, 4, 1, 1, 2, 1, 2, 2, 1, 1, 4, 2, 1, 1, 2, 1],
        [2, 2, 4, 2, 4, 4, 16, 8, 2, 1, 1, 1, 4, 2, 1, 1],
        [1, 1, 2, 1, 2, 2, 8, 4, 2, 1, 1, 1, 4, 2, 1, 1],
        [4, 2, 4, 4, 16, 8, 2, 2, 1, 1, 2, 1, 1, 1, 4, 2],
        [2, 1, 2, 2, 8, 4, 1, 1, 1, 1, 2, 1, 1, 1, 4, 2],
        [4, 4, 16, 8, 1, 1, 2, 1, 4, 2, 1, 1, 4, 2, 2, 2],
        [2, 2, 8, 4, 1, 1, 2, 1, 4, 2, 1, 1, 2, 1, 1, 1],
        [1, 1, 2, 1, 1, 1, 4, 2, 4, 4, 16, 8, 2, 2, 4, 2],
        [1, 1, 2, 1, 1, 1, 4, 2, 2, 2, 8, 4, 1, 1, 2, 1],
        [4, 2, 1, 1, 2, 1, 1, 1, 4, 2, 2, 2, 16, 8, 4, 4],
        [4, 2, 1, 1, 2, 1, 1, 1, 2, 1, 1, 1, 8, 4, 2, 2],
    ]

    private static func power(_ exponent: Int) -> Int {
        var result = 1, base = 45, e = exponent
        while e > 0 {
            if e & 1 != 0 { result = result * base % 257 }
            base = base * base % 257
            e >>= 1
        }
        return result
    }

    private static func selected(_ i: Int) -> Bool { (0x9999 & (1 << i)) != 0 }

    private static func mix(_ a: UInt8, _ b: UInt8, _ i: Int) -> UInt8 {
        selected(i) ? a ^ b : a &+ b
    }

    static func response(to challenge: [UInt8]) -> [UInt8] {
        precondition(challenge.count == 16)
        let exp = (0..<256).map { UInt8(truncatingIfNeeded: power($0)) }
        var log = [UInt8](repeating: 128, count: 256)
        for i in 1..<256 {
            let e = power(i)
            if e != 256 { log[e] = UInt8(i) }
        }
        var key = challenge
        key[15] ^= 6
        var register = key + [key.reduce(0, ^)]
        var keys = [key]
        for k in 1...16 {
            register = register.map { ($0 << 5) | ($0 >> 3) }
            var roundKey: [UInt8] = []
            for i in 0..<16 {
                let exponent = 17 * (k + 1) + i + 1
                let bias = UInt8(truncatingIfNeeded: power(power(exponent)))
                roundKey.append(register[(k + i) % 17] &+ bias)
            }
            keys.append(roundKey)
        }
        var result = plaintext
        for round in 0..<8 {
            if round == 2 {
                result = (0..<16).map { mix(result[$0], plaintext[$0], $0) }
            }
            result = (0..<16).map { mix(result[$0], keys[round * 2][$0], $0) }
            result = (0..<16).map { selected($0) ? exp[Int(result[$0])] : log[Int(result[$0])] }
            result = (0..<16).map { i in
                selected(i) ? keys[round * 2 + 1][i] &+ result[i] : keys[round * 2 + 1][i] ^ result[i]
            }
            let previous = result
            result = (0..<16).map { i in
                UInt8(truncatingIfNeeded: (0..<16).reduce(0) { $0 + coefficients[i][$1] * Int(previous[$1]) })
            }
        }
        return (0..<16).map { mix(keys[16][$0], result[$0], $0) }
    }
}