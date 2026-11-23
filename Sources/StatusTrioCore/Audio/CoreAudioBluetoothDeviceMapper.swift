import CoreAudio
import Foundation

/// One discovered CoreAudio output endpoint that could back a listening-mode
/// control, paired with the identity evidence the mapper reasons over.
///
/// The endpoint carries a `bluetoothAddress` — the normalized Bluetooth address the
/// HAL transport resolves *to*, not a guess from the device name — and a flag for
/// whether it is the current default output. The address is optional precisely
/// because establishing it from CoreAudio without a trusted source is not always
/// possible; when it is absent the mapper falls back to the conservative single-
/// device rule rather than matching names.
struct BluetoothListeningModeEndpoint: Equatable, Sendable {
    let audioDeviceID: AudioDeviceID
    let capability: BluetoothListeningModeCapability
    let isDefaultOutput: Bool
    let bluetoothAddress: String?
}

/// The CoreAudio → Bluetooth identity resolution the plan calls its most important
/// safety boundary (§6).
///
/// It answers one question per connected device: which endpoint, if any, is safe to
/// write to. The rules are ordered:
///
/// 1. An exact, trusted address match resolves the device — but only when exactly
///    one controllable endpoint carries that address. Two sibling endpoints (an
///    input and an output for the same buds) sharing an address is ambiguity, and
///    ambiguity fails closed rather than picking one.
/// 2. With no address evidence at all, a single connected AirPods, a single
///    controllable endpoint, and that endpoint being the default output is the only
///    configuration trusted enough to act on (§6's accepted fallback). Anything
///    looser — multiple AirPods, multiple endpoints, a non-default output — returns
///    nil, so no button appears and no wrong device is ever written.
///
/// There is deliberately no name matching here: fuzzy name evidence is forbidden
/// because writing on it can commandeer a different device than the row shows.
enum BluetoothListeningModeEndpointMapper {
    static func endpointID(
        forNormalizedAddress address: String,
        connectedEligibleAirPodsCount: Int,
        in endpoints: [BluetoothListeningModeEndpoint]
    ) -> AudioDeviceID? {
        let controllable = endpoints.filter { $0.capability.isControllable }
        guard !controllable.isEmpty else { return nil }

        // (1) Exact address match on endpoints that carry trusted address evidence.
        let normalizedTarget = BluetoothBatteryReader.normalizedAddress(address)
        guard !normalizedTarget.isEmpty else {
            return conservativeFallback(controllable, connectedEligibleAirPodsCount: connectedEligibleAirPodsCount)
        }

        let matches = controllable.filter { endpoint in
            guard let endpointAddress = endpoint.bluetoothAddress else { return false }
            return BluetoothBatteryReader.normalizedAddress(endpointAddress) == normalizedTarget
        }

        if matches.count == 1 { return matches[0].audioDeviceID }
        // Two or more endpoints claim the same address, or none does: neither is a
        // safe write target. When none carries the address we still allow the
        // conservative fallback, because absence of evidence is not a conflict.
        if matches.count > 1 { return nil }
        return conservativeFallback(controllable, connectedEligibleAirPodsCount: connectedEligibleAirPodsCount)
    }

    /// §6's accepted fallback: only a wholly unambiguous single-device, single-
    /// endpoint, current-default-output configuration is trusted.
    private static func conservativeFallback(
        _ controllable: [BluetoothListeningModeEndpoint],
        connectedEligibleAirPodsCount: Int
    ) -> AudioDeviceID? {
        guard connectedEligibleAirPodsCount == 1,
              controllable.count == 1,
              controllable[0].bluetoothAddress == nil,
              controllable[0].isDefaultOutput else {
            return nil
        }
        return controllable[0].audioDeviceID
    }
}

/// Supplies the endpoints a device row can be matched to. Behind a seam so the
/// controller's wiring and the mapper's rules are testable without CoreAudio.
protocol CoreAudioBluetoothEndpointProviding: Sendable {
    /// Discovers the current controllable listening-mode output endpoints. Called
    /// on a panel-visible refresh, never on a timer.
    func discoverEndpoints(using hal: BluetoothListeningModeHAL) -> [BluetoothListeningModeEndpoint]
}

/// The production endpoint provider.
///
/// Enumerates output capabilities and reads exact Bluetooth address UIDs from
/// HAL. Unrecognized UID formats carry no identity evidence and retain the
/// conservative single-device fallback. Device names are never matched.
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
                bluetoothAddress: bluetoothAddress(for: deviceID)
            )
        }
    }

    private func bluetoothAddress(for deviceID: AudioDeviceID) -> String? {
        var property = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(deviceID, &property, 0, nil, &size, &uid) == noErr,
              let uid else { return nil }
        return HuaweiAudioEndpointMatcher.bluetoothAddress(in: uid as String)
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
