import CoreAudio
import Foundation

enum BluetoothListeningModePropertyKind: Hashable, Sendable {
    case appleAudioDevice
    case listeningMode
    case listeningModeSupport
}

enum BluetoothListeningModeProperty {
    static let expectedSize = UInt32(MemoryLayout<UInt32>.size)
}

/// The narrow set of HAL operations the adapter needs, behind a seam.
///
/// Everything here is a global-scope, main-element, four-byte property read or
/// write, which is exactly the shape `lstm` and `lsms` have. Keeping the seam this
/// small means the adapter's logic — the runtime gate and the bounded read-back —
/// is testable against a fake that never touches CoreAudio.
protocol BluetoothListeningModePropertyReading: Sendable {
    func hasProperty(_ deviceID: AudioDeviceID, _ property: BluetoothListeningModePropertyKind) -> Bool
    func dataSize(_ deviceID: AudioDeviceID, _ property: BluetoothListeningModePropertyKind) -> UInt32?
    func readUInt32(_ deviceID: AudioDeviceID, _ property: BluetoothListeningModePropertyKind) -> UInt32?
    func isSettable(_ deviceID: AudioDeviceID, _ property: BluetoothListeningModePropertyKind) -> Bool
    func writeUInt32(_ deviceID: AudioDeviceID, _ property: BluetoothListeningModePropertyKind, _ value: UInt32) -> OSStatus
}

/// The delay injected between read-back attempts.
///
/// Production sleeps on the clock; a test supplies an immediate sleeper so the
/// sixteen-attempt budget runs without actually costing eight hundred milliseconds.
protocol BluetoothListeningModeSleeping: Sendable {
    func sleep(for duration: Duration) async
}

/// The production sleeper, delegating to structured concurrency.
struct ClockBluetoothListeningModeSleeper: BluetoothListeningModeSleeping {
    func sleep(for duration: Duration) async {
        try? await Task.sleep(for: duration)
    }
}

struct UnavailableBluetoothListeningModeBackend: BluetoothListeningModePropertyReading {
    func hasProperty(_ deviceID: AudioDeviceID, _ property: BluetoothListeningModePropertyKind) -> Bool { false }
    func dataSize(_ deviceID: AudioDeviceID, _ property: BluetoothListeningModePropertyKind) -> UInt32? { nil }
    func readUInt32(_ deviceID: AudioDeviceID, _ property: BluetoothListeningModePropertyKind) -> UInt32? { nil }
    func isSettable(_ deviceID: AudioDeviceID, _ property: BluetoothListeningModePropertyKind) -> Bool { false }
    func writeUInt32(
        _ deviceID: AudioDeviceID,
        _ property: BluetoothListeningModePropertyKind,
        _ value: UInt32
    ) -> OSStatus { kAudioHardwareUnspecifiedError }
}

/// The capability reader and mode writer built on the property seam.
///
/// This is the boundary the plan asks for: the view never calls `AudioObject…`,
/// and the raw `UInt32` values never escape the adapter. It owns two rules that
/// are easy to get wrong and easy to test — the runtime gate that decides whether
/// a device is controllable at all, and the bounded read-back that decides
/// whether a write actually landed.
struct BluetoothListeningModeHAL {
    let backend: any BluetoothListeningModePropertyReading
    let sleeper: any BluetoothListeningModeSleeping
    /// The read-back budget. The HAL can update its cache before the device
    /// confirms, so a write is trusted only once `lstm` settles on the target —
    /// polled at `retryDelay` for at most `retryAttempts` times.
    let retryAttempts: Int
    let retryDelay: Duration

    init(
        backend: any BluetoothListeningModePropertyReading = UnavailableBluetoothListeningModeBackend(),
        sleeper: any BluetoothListeningModeSleeping = ClockBluetoothListeningModeSleeper(),
        retryAttempts: Int = 16,
        retryDelay: Duration = .milliseconds(50)
    ) {
        self.backend = backend
        self.sleeper = sleeper
        self.retryAttempts = retryAttempts
        self.retryDelay = retryDelay
    }

    /// Builds a device's capability, or `nil` when it is not a controllable
    /// listening-mode endpoint.
    ///
    /// The gate is strict and fails closed: `lstm` must exist, be four bytes, be
    /// readable and be settable; `lsms` must exist, be four bytes and be readable.
    /// Any miss yields `nil`, so the UI never shows a half-working control, and a
    /// system update that removes the properties simply makes them disappear.
    func capability(for deviceID: AudioDeviceID) -> BluetoothListeningModeCapability? {
        guard
            backend.hasProperty(deviceID, .listeningMode),
            backend.dataSize(deviceID, .listeningMode)
                == BluetoothListeningModeProperty.expectedSize,
            let rawMode = backend.readUInt32(deviceID, .listeningMode),
            backend.hasProperty(deviceID, .listeningModeSupport),
            backend.dataSize(deviceID, .listeningModeSupport)
                == BluetoothListeningModeProperty.expectedSize,
            let supportMask = backend.readUInt32(deviceID, .listeningModeSupport)
        else {
            return nil
        }

        let canSet = backend.isSettable(deviceID, .listeningMode)
        return BluetoothListeningModeCapability(
            audioDeviceID: deviceID,
            availableModes: BluetoothListeningModeSupport.availableModes(from: supportMask),
            currentMode: BluetoothListeningModeRawValue.mode(from: rawMode),
            canSet: canSet
        )
    }

    /// The device's current mode, or `nil` for an absent/unreadable/unknown value.
    func currentMode(for deviceID: AudioDeviceID) -> BluetoothListeningMode? {
        guard let raw = backend.readUInt32(deviceID, .listeningMode) else {
            return nil
        }
        return BluetoothListeningModeRawValue.mode(from: raw)
    }

    /// Whether the device still supports `mode` right now, re-checked before a
    /// write so a capability that changed since discovery cannot be written to.
    func supports(_ mode: BluetoothListeningMode, for deviceID: AudioDeviceID) -> Bool {
        guard mode.isUserSelectable,
              let bit = mode.supportBit,
              let mask = backend.readUInt32(deviceID, .listeningModeSupport) else {
            return false
        }
        return mask & bit != 0
    }

    /// Asks the device to switch to `mode`, then confirms it through a bounded,
    /// delayed read-back.
    ///
    /// The order is deliberate: re-verify support and settability (a capability may
    /// have changed since discovery), skip the write when already on target, write,
    /// then trust only a matching read-back — not the setter's `noErr`, which just
    /// means the control surface accepted the request.
    func setMode(
        _ mode: BluetoothListeningMode,
        for deviceID: AudioDeviceID
    ) async -> BluetoothListeningModeWriteResult {
        guard mode.isUserSelectable else {
            return .failed(.modeUnsupported)
        }

        // Re-verify the live gate before touching anything.
        guard backend.hasProperty(deviceID, .listeningMode),
              let currentRaw = backend.readUInt32(deviceID, .listeningMode) else {
            return .failed(.propertyUnavailable)
        }
        guard supports(mode, for: deviceID) else {
            return .failed(.modeUnsupported)
        }
        guard backend.isSettable(deviceID, .listeningMode) else {
            return .failed(.notSettable)
        }

        // Already on target: no write, and nothing to read back. This is what keeps
        // a re-tap of the selected capsule from issuing a redundant request.
        if BluetoothListeningModeRawValue.mode(from: currentRaw) == mode {
            return .confirmed(mode)
        }

        let status = backend.writeUInt32(
            deviceID,
            .listeningMode,
            mode.rawValue
        )
        guard status == noErr else {
            return .failed(.setterFailed(status: status))
        }

        return await confirmWrite(of: mode, for: deviceID)
    }

    /// Polls `lstm` until it reads back as `mode` or the budget runs out.
    ///
    /// Sleeps *before* each read, mirroring the plan's "wait 50 ms, then read"
    /// first step — the cache settles asynchronously, so an immediate read would
    /// still show the pre-write value. If the property vanishes mid-poll, the loop
    /// stops and reports the last observed mode (`nil`), letting the caller fall
    /// back rather than spin.
    private func confirmWrite(
        of mode: BluetoothListeningMode,
        for deviceID: AudioDeviceID
    ) async -> BluetoothListeningModeWriteResult {
        var lastObserved: BluetoothListeningMode?
        for _ in 0..<max(1, retryAttempts) {
            await sleeper.sleep(for: retryDelay)

            guard let raw = backend.readUInt32(deviceID, .listeningMode) else {
                // The property disappeared; there is nothing left to confirm against.
                return .unconfirmed(observed: nil)
            }
            let observed = BluetoothListeningModeRawValue.mode(from: raw)
            lastObserved = observed
            if observed == mode {
                return .confirmed(mode)
            }
        }
        return .unconfirmed(observed: lastObserved)
    }
}
