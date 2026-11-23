import CoreAudio
import Foundation
import os

// Store-only stand-ins for the Direct-only DDC kernel types. The App Store build
// cannot touch IOAVService/I2C, so these report "no display / no data" and every
// write is refused. They exist so shared monitors (VolumeMonitor,
// DDCBrightnessCoordinator) compile unchanged; DDC is simply unavailable in Store.
// Types defined in already-included files (DDCVolumeReply, DDCVolumeReadResult,
// DDCVolumeCapability, DDCVolumeReplyKind, DDCReadFailure) are NOT redefined here.

let ddcTargetLogger = Logger(subsystem: "com.lingsmbp.StatusTrio", category: "DDCTarget")

enum DDCLogSession {
    static let id = "store"
}

enum DDCGetVCPChecksumMode: Equatable, Sendable {
    case standard
    case legacy
    var includesDataAddress: Bool { self == .standard }
}

enum DDCPacket {
    static let chipAddress: UInt32 = 0x37
    static let dataAddress: UInt32 = 0x51
    static let volumeVCP: UInt8 = 0x62
    static let brightnessVCP: UInt8 = 0x10

    static func getVCPRequest(vcp: UInt8 = volumeVCP, checksumMode: DDCGetVCPChecksumMode) -> [UInt8] {
        [0x80 | 2, 0x01, vcp]
    }

    static func setVCPRequest(vcp: UInt8 = volumeVCP, value: UInt16) -> [UInt8] {
        [0x80 | 4, 0x03, vcp, UInt8(value >> 8), UInt8(value & 0xff)]
    }

    static func checksum(_ payload: [UInt8], includeDataAddress: Bool) -> UInt8 { 0 }
}

final class DDCDisplayTarget {
    let uid: String
    init(uid: String) { self.uid = uid }
}

protocol DDCVolumeTransport: AnyObject {
    func resolve(uid: String) -> DDCDisplayTarget?
    func read(_ target: DDCDisplayTarget) -> DDCVolumeReadResult
    func write(_ target: DDCDisplayTarget, value: UInt16) -> Bool
}

protocol DDCFeatureTransport: DDCVolumeTransport {
    func read(_ target: DDCDisplayTarget, feature: UInt8) -> DDCVolumeReadResult
    func write(_ target: DDCDisplayTarget, value: UInt16, feature: UInt8) -> Bool
}

final class DDCDisplayTransport: DDCFeatureTransport {
    init() {}
    func resolve(uid: String) -> DDCDisplayTarget? { nil }
    func read(_ target: DDCDisplayTarget) -> DDCVolumeReadResult { .failure(.serviceUnavailable) }
    func write(_ target: DDCDisplayTarget, value: UInt16) -> Bool { false }
    func read(_ target: DDCDisplayTarget, feature: UInt8) -> DDCVolumeReadResult { .failure(.serviceUnavailable) }
    func write(_ target: DDCDisplayTarget, value: UInt16, feature: UInt8) -> Bool { false }
}

struct DDCVolumeUpdate: Sendable {
    let outputID: AudioDeviceID
    let uid: String
    let generation: UInt64
    let capability: DDCVolumeCapability
    let commandID: UInt64?
    var scalar: Double? { capability.scalar }
}

final class DDCVolumeCoordinator {
    typealias Sleep = @Sendable (Duration) async throws -> Void
    typealias WatchdogSleep = @Sendable (Duration) async throws -> Void
    typealias WatchdogTimeoutHandler = @MainActor (_ generation: UInt64, _ commandID: UInt64?) -> Void

    private(set) var generation: UInt64 = 0

    init(
        transport: DDCVolumeTransport = DDCDisplayTransport(),
        readWatchdog: Duration = .seconds(2),
        watchdogSleep: @escaping WatchdogSleep = { try await Task.sleep(for: $0) },
        onWatchdogTimeout: @escaping WatchdogTimeoutHandler = { _, _ in },
        onUpdate: @escaping @MainActor (DDCVolumeUpdate) -> Void
    ) {}

    func select(outputID: AudioDeviceID, uid: String?) {}
    func topologyChanged() {}
    func setDetailsVisible(_ visible: Bool) {}
    func setDisplayAsleep(_ asleep: Bool) {}
    func setVolume(_ scalar: Double) -> UInt64? { nil }
    func flushPendingVolume() {}
    func refresh() {}
    func stop() {}
}

enum BetterDisplayFramebufferReader {
    static func readInBackground() async -> [BetterDisplayFramebufferIdentity] { [] }
    static func read() -> [BetterDisplayFramebufferIdentity] { [] }
}
