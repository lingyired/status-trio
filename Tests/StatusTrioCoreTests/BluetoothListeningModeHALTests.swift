import CoreAudio
import Foundation
import XCTest

@testable import StatusTrioCore

/// A scripted stand-in for the HAL property seam, so the runtime gate and the
/// bounded read-back can be exercised without a CoreAudio device.
///
/// It runs in one of two modes for `lstm` reads. When `lstmReadScript` is set, each
/// read returns the next scripted value (the last value repeats once the script is
/// exhausted) — that is how a test simulates the cache settling late, or a property
/// that vanishes mid-poll. Otherwise `lstm` reads a stored value and a write
/// updates it immediately, modelling a device that confirms on the first read-back.
final class FakeListeningModeBackend: BluetoothListeningModePropertyReading, @unchecked Sendable {
    struct Slot {
        var exists = true
        var size = UInt32(MemoryLayout<UInt32>.size)
        var value: UInt32 = 0
        var settable = true
    }

    var lstm = Slot(value: 2)
    var lsms = Slot(value: 0b111)
    var writeStatus: OSStatus = noErr
    var lstmReadScript: [UInt32?]?
    private(set) var writeCount = 0

    private let lock = NSLock()

    func hasProperty(_ deviceID: AudioDeviceID, _ property: BluetoothListeningModePropertyKind) -> Bool {
        slot(for: property).exists
    }

    func dataSize(_ deviceID: AudioDeviceID, _ property: BluetoothListeningModePropertyKind) -> UInt32? {
        let slot = slot(for: property)
        return slot.exists ? slot.size : nil
    }

    func readUInt32(_ deviceID: AudioDeviceID, _ property: BluetoothListeningModePropertyKind) -> UInt32? {
        if property == .listeningMode {
            return readListeningMode()
        }
        let slot = slot(for: property)
        return slot.exists ? slot.value : nil
    }

    func isSettable(_ deviceID: AudioDeviceID, _ property: BluetoothListeningModePropertyKind) -> Bool {
        slot(for: property).settable
    }

    func writeUInt32(
        _ deviceID: AudioDeviceID,
        _ property: BluetoothListeningModePropertyKind,
        _ value: UInt32
    ) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        guard property == .listeningMode, lstm.exists, lstm.settable else {
            return kAudioHardwareUnspecifiedError
        }
        writeCount += 1
        guard writeStatus == noErr else { return writeStatus }
        // A confirming device: the stored value becomes the target, unless a script
        // is driving reads, in which case the script owns what a read reports.
        if lstmReadScript == nil {
            lstm.value = value
        }
        return noErr
    }

    // MARK: - Read scripting

    private func readListeningMode() -> UInt32? {
        lock.lock()
        defer { lock.unlock() }
        guard let script = lstmReadScript else {
            return lstm.exists ? lstm.value : nil
        }
        guard !script.isEmpty else { return nil }
        let index = min(readCursor, script.count - 1)
        readCursor += 1
        guard index < script.count, let raw = script[index] else { return nil }
        return raw
    }

    private var readCursor = 0

    private func slot(for property: BluetoothListeningModePropertyKind) -> Slot {
        property == .listeningMode ? lstm : lsms
    }
}

/// A sleeper that returns instantly, so the sixteen-attempt read-back budget costs
/// nothing in tests while still exercising every branch of the poll loop.
struct ImmediateListeningModeSleeper: BluetoothListeningModeSleeping {
    func sleep(for duration: Duration) async {}
}

final class BluetoothListeningModeHALTests: XCTestCase {
    private let device: AudioDeviceID = 42

    private func makeHAL(
        _ backend: FakeListeningModeBackend,
        attempts: Int = 16,
        delay: Duration = .milliseconds(50)
    ) -> BluetoothListeningModeHAL {
        BluetoothListeningModeHAL(
            backend: backend,
            sleeper: ImmediateListeningModeSleeper(),
            retryAttempts: attempts,
            retryDelay: delay
        )
    }

    // MARK: - Runtime gate (§5.2)

    func testCapabilityNilWhenListeningModeMissing() {
        let backend = FakeListeningModeBackend()
        backend.lstm.exists = false
        XCTAssertNil(makeHAL(backend).capability(for: device))
    }

    func testCapabilityNilWhenSupportMissing() {
        let backend = FakeListeningModeBackend()
        backend.lsms.exists = false
        XCTAssertNil(makeHAL(backend).capability(for: device))
    }

    func testCapabilityNilWhenWrongPropertySize() {
        let backend = FakeListeningModeBackend()
        backend.lstm.size = 8
        XCTAssertNil(makeHAL(backend).capability(for: device))
    }

    func testCapabilityReportsCanSetFalseWhenNotSettable() {
        let backend = FakeListeningModeBackend()
        backend.lstm.settable = false
        let capability = makeHAL(backend).capability(for: device)
        // The gate passes (readable, right size) so a capability is returned, but
        // `canSet` is false, and a non-settable device is never controllable.
        XCTAssertNotNil(capability)
        XCTAssertEqual(capability?.canSet, false)
        XCTAssertEqual(capability?.isControllable, false)
    }

    // MARK: - Support-mask parsing (§18.1)

    func testSupportMaskSingleModeIsNotControllable() {
        let backend = FakeListeningModeBackend()
        backend.lsms.value = 0b001
        let capability = makeHAL(backend).capability(for: device)
        XCTAssertEqual(capability?.availableModes, [.noiseCancellation])
        XCTAssertEqual(capability?.isControllable, false, "one mode has nothing to switch between")
    }

    func testSupportMaskTwoModes() {
        let backend = FakeListeningModeBackend()
        backend.lsms.value = 0b011
        XCTAssertEqual(
            makeHAL(backend).capability(for: device)?.availableModes,
            [.noiseCancellation, .transparency]
        )
    }

    func testSupportMaskThreeModesInDisplayOrder() {
        let backend = FakeListeningModeBackend()
        backend.lsms.value = 0b111
        XCTAssertEqual(
            makeHAL(backend).capability(for: device)?.availableModes,
            [.noiseCancellation, .transparency, .adaptive]
        )
    }

    func testUnknownSupportBitsKeepRecognizedModes() {
        let backend = FakeListeningModeBackend()
        backend.lsms.value = 0b1_0111 // a future bit at position 3 plus all three known
        let capability = makeHAL(backend).capability(for: device)
        XCTAssertEqual(capability?.availableModes, [.noiseCancellation, .transparency, .adaptive])
        XCTAssertTrue(
            BluetoothListeningModeSupport.hasUnknownBits(backend.lsms.value),
            "the unknown bit is reported, never promoted to a mode"
        )
    }

    // MARK: - Current-mode parsing (§18.1)

    func testCurrentZeroIsUnknownAndFailsClosed() {
        let backend = FakeListeningModeBackend()
        backend.lstm.value = 0
        XCTAssertNil(makeHAL(backend).capability(for: device)?.currentMode)
    }

    func testCurrentOffIsObservedButNotSelectable() {
        let backend = FakeListeningModeBackend()
        backend.lstm.value = 1
        let capability = makeHAL(backend).capability(for: device)
        XCTAssertEqual(capability?.currentMode, .off)
        XCTAssertFalse(BluetoothListeningMode.off.isUserSelectable)
    }

    func testCurrentModesMapToTheirRawValues() {
        let mapping: [(UInt32, BluetoothListeningMode)] = [
            (2, .noiseCancellation), (3, .transparency), (4, .adaptive)
        ]
        for (raw, mode) in mapping {
            let backend = FakeListeningModeBackend()
            backend.lstm.value = raw
            XCTAssertEqual(makeHAL(backend).capability(for: device)?.currentMode, mode)
        }
    }

    func testUnknownCurrentRawFailsClosed() {
        let backend = FakeListeningModeBackend()
        backend.lstm.value = 9
        XCTAssertNil(makeHAL(backend).capability(for: device)?.currentMode)
    }

    // MARK: - Write + bounded read-back (§5.3)

    func testIdempotentTargetDoesNotWrite() async {
        let backend = FakeListeningModeBackend()
        backend.lstm.value = 3 // already Transparency
        let result = await makeHAL(backend).setMode(.transparency, for: device)
        XCTAssertEqual(result, .confirmed(.transparency))
        XCTAssertEqual(backend.writeCount, 0, "a re-tap of the selected mode writes nothing")
    }

    func testSetterFailureIsReported() async {
        let backend = FakeListeningModeBackend()
        backend.lstm.value = 2 // NC
        backend.writeStatus = kAudioHardwareBadObjectError
        let result = await makeHAL(backend).setMode(.transparency, for: device)
        XCTAssertEqual(result, .failed(.setterFailed(status: kAudioHardwareBadObjectError)))
    }

    func testWriteThenDelayedMatchingReadbackConfirms() async {
        let backend = FakeListeningModeBackend()
        backend.lstm.value = 2 // start on NC
        // The cache lags: it still reports NC twice, then settles on Transparency.
        backend.lstmReadScript = [2, 2, 3]
        let result = await makeHAL(backend).setMode(.transparency, for: device)
        XCTAssertEqual(result, .confirmed(.transparency))
        XCTAssertEqual(backend.writeCount, 1)
    }

    func testEventualMismatchIsUnconfirmed() async {
        let backend = FakeListeningModeBackend()
        backend.lstm.value = 2
        // Never settles on the target — every read stays on NC.
        backend.lstmReadScript = [2, 2, 2]
        let hal = makeHAL(backend, attempts: 4)
        let result = await hal.setMode(.transparency, for: device)
        XCTAssertEqual(result, .unconfirmed(observed: .noiseCancellation))
    }

    func testPropertyDisappearsDuringReadback() async {
        let backend = FakeListeningModeBackend()
        backend.lstm.value = 2
        // Present for the pre-write read and the write, then gone for the read-back.
        backend.lstmReadScript = [2, nil]
        let result = await makeHAL(backend).setMode(.transparency, for: device)
        XCTAssertEqual(result, .unconfirmed(observed: nil))
    }

    func testCapabilityChangeBeforeWriteRejectsUnsupportedMode() async {
        let backend = FakeListeningModeBackend()
        backend.lstm.value = 2
        backend.lsms.value = 0b001 // NC only — Adaptive is no longer supported
        let result = await makeHAL(backend).setMode(.adaptive, for: device)
        XCTAssertEqual(result, .failed(.modeUnsupported))
        XCTAssertEqual(backend.writeCount, 0)
    }

    func testWriteToOffIsRejected() async {
        let backend = FakeListeningModeBackend()
        backend.lstm.value = 2
        let result = await makeHAL(backend).setMode(.off, for: device)
        XCTAssertEqual(result, .failed(.modeUnsupported), "V1 never switches to Off")
    }
}
