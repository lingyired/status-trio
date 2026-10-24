import CoreAudio
import Foundation

/// Enumerates CoreAudio output endpoints and asks the Direct HAL to gate them.
struct CoreAudioBluetoothListeningModeEndpointProvider: CoreAudioBluetoothEndpointProviding {
    init() {}

    func discoverEndpoints(using hal: BluetoothListeningModeHAL) -> [BluetoothListeningModeEndpoint] {
        let deviceIDs = Self.outputDeviceIDs()
        let defaultID = Self.defaultOutputDeviceID()

        return deviceIDs.compactMap { deviceID -> BluetoothListeningModeEndpoint? in
            guard let capability = hal.capability(for: deviceID) else { return nil }
            return BluetoothListeningModeEndpoint(
                audioDeviceID: deviceID,
                capability: capability,
                isDefaultOutput: deviceID == defaultID,
                bluetoothAddress: nil
            )
        }
    }

    private static func outputDeviceIDs() -> [AudioDeviceID] {
        guard let ids = uint32ArrayProperty(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDevices,
            scope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal)
        ) else {
            return []
        }
        return ids.filter(hasOutputStream)
    }

    private static func hasOutputStream(_ deviceID: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeOutput),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &size) == noErr else { return false }
        return size >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    private static func uint32ArrayProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> [AudioDeviceID]? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(objectID, &addr, 0, nil, &size) == noErr else { return nil }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }
        var ids = Array(repeating: AudioDeviceID(kAudioObjectUnknown), count: count)
        var mutable = size
        let status = ids.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(objectID, &addr, 0, nil, &mutable, buffer.baseAddress!)
        }
        guard status == noErr else { return nil }
        return ids.filter { $0 != AudioDeviceID(kAudioObjectUnknown) }
    }
}
