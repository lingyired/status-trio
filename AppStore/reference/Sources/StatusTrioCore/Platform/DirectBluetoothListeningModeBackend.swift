import CoreAudio
import Foundation

/// Apple-private CoreAudio selectors stay in the Direct source closure.
enum DirectBluetoothListeningModeProperty {
    static let appleAudioDevice: AudioObjectPropertySelector = 0x6961_6170
    static let listeningMode: AudioObjectPropertySelector = 0x6C73_746D
    static let listeningModeSupport: AudioObjectPropertySelector = 0x6C73_6D73
    static let scope = AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal)
    static let element = AudioObjectPropertyElement(kAudioObjectPropertyElementMain)

    static func selector(for kind: BluetoothListeningModePropertyKind) -> AudioObjectPropertySelector {
        switch kind {
        case .appleAudioDevice: appleAudioDevice
        case .listeningMode: listeningMode
        case .listeningModeSupport: listeningModeSupport
        }
    }

    static func address(_ kind: BluetoothListeningModePropertyKind) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector(for: kind),
            mScope: scope,
            mElement: element
        )
    }
}

struct CoreAudioBluetoothListeningModeBackend: BluetoothListeningModePropertyReading {
    init() {}

    func hasProperty(_ deviceID: AudioDeviceID, _ property: BluetoothListeningModePropertyKind) -> Bool {
        var address = DirectBluetoothListeningModeProperty.address(property)
        return AudioObjectHasProperty(deviceID, &address)
    }

    func dataSize(_ deviceID: AudioDeviceID, _ property: BluetoothListeningModePropertyKind) -> UInt32? {
        var address = DirectBluetoothListeningModeProperty.address(property)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else {
            return nil
        }
        return size
    }

    func readUInt32(_ deviceID: AudioDeviceID, _ property: BluetoothListeningModePropertyKind) -> UInt32? {
        var address = DirectBluetoothListeningModeProperty.address(property)
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    func isSettable(_ deviceID: AudioDeviceID, _ property: BluetoothListeningModePropertyKind) -> Bool {
        var address = DirectBluetoothListeningModeProperty.address(property)
        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr
            && settable.boolValue
    }

    func writeUInt32(
        _ deviceID: AudioDeviceID,
        _ property: BluetoothListeningModePropertyKind,
        _ value: UInt32
    ) -> OSStatus {
        var address = DirectBluetoothListeningModeProperty.address(property)
        var mutableValue = value
        return AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &mutableValue
        )
    }
}
