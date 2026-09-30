import CoreAudio
import Foundation

/// The `AudioObjectPropertyListenerBlock` seam.
///
/// `lstm` is the only property we subscribe to, and it is always read at global
/// scope / main element (see `BluetoothListeningModeProperty.address(_:)`). The
/// block is a Swift closure bridged to the ObjC block that CoreAudio expects; the
/// same Swift closure value must be handed back for removal, so callers keep the
/// block reference alive rather than constructing a fresh one on each call.
///
/// `AudioObjectPropertyListenerBlock` in the macOS SDK takes `(count, addresses)`.
/// We do not read the address list — the only subscribed selector is `lstm`, so any
/// signal means "re-read the current mode" — hence the `_` params at every call.
protocol BluetoothListeningModePropertyListening: Sendable {
    func addListener(
        deviceID: AudioDeviceID,
        address: AudioObjectPropertyAddress,
        queue: DispatchQueue?,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus

    func removeListener(
        deviceID: AudioDeviceID,
        address: AudioObjectPropertyAddress,
        queue: DispatchQueue?,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus
}

/// The production listener backend, delegating to the AudioObject block API.
///
/// `AudioObjectAdd/RemovePropertyListenerBlock` are the only calls needed. CoreAudio
/// owns the retain, so the caller is responsible for keeping the exact block
/// reference until the removal happens.
struct CoreAudioBluetoothListeningModeListenerBackend: BluetoothListeningModePropertyListening {
    init() {}

    func addListener(
        deviceID: AudioDeviceID,
        address: AudioObjectPropertyAddress,
        queue: DispatchQueue?,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus {
        var mutableAddress = address
        return AudioObjectAddPropertyListenerBlock(deviceID, &mutableAddress, queue, block)
    }

    func removeListener(
        deviceID: AudioDeviceID,
        address: AudioObjectPropertyAddress,
        queue: DispatchQueue?,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus {
        var mutableAddress = address
        return AudioObjectRemovePropertyListenerBlock(deviceID, &mutableAddress, queue, block)
    }
}

/// The bookkeeping the controller stores per subscribed endpoint so the block
/// identity survives between `addListener` and `removeListener`.
///
/// `AudioObjectRemovePropertyListenerBlock` identifies a subscription by
/// (deviceID, address, queue, block). Two Swift closures with identical bodies are
/// different objects, so re-creating the closure on the way out would leave the
/// CoreAudio-side registration dangling and a later real change would fire into a
/// half-dead controller. Storing the same block reference here keeps the identity
/// stable across the add/remove pair.
struct BluetoothListeningModeSubscription {
    let deviceID: AudioDeviceID
    let address: AudioObjectPropertyAddress
    let queue: DispatchQueue
    let block: AudioObjectPropertyListenerBlock
}
