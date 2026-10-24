import CoreAudio
import Foundation

/// Direct-only listener for the undocumented listening-mode selector.
struct CoreAudioBluetoothListeningModeListenerBackend: BluetoothListeningModePropertyListening {
    init() {}

    var listeningModeAddress: AudioObjectPropertyAddress? {
        DirectBluetoothListeningModeProperty.address(.listeningMode)
    }

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
