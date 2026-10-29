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

struct UnavailableBluetoothListeningModeEndpointProvider: CoreAudioBluetoothEndpointProviding {
    func discoverEndpoints(using hal: BluetoothListeningModeHAL) -> [BluetoothListeningModeEndpoint] {
        []
    }
}

/// The production endpoint provider.
///
/// It enumerates the CoreAudio output devices, builds each device's capability
/// through the runtime-gated HAL, and marks the current default output. It resolves
/// no Bluetooth address: no public CoreAudio property carries the peer MAC, and the
/// plan forbids inventing one from the device name. With the address left `nil`,
/// resolution uses §6's conservative single-device fallback — which means the
/// control surfaces only for the AirPods that are the current default output,
/// exactly the limitation §3.3 Case A accepts. A follow-up may add a trusted
/// IOBluetooth address resolver here without changing the mapper's rules.
