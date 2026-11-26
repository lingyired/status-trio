import AppKit
import Foundation

// Phase-1 compatibility: the merged main resolver exposes `inputs` only, while
// the retained V1 plugin/resolver layer and its tests still need the derived
// source-availability snapshot from the pre-merge implementation.
@MainActor
extension IconPresentationResourceResolver {
    static func sourceSnapshot(
        snapshot: StatusSnapshot,
        bluetoothDevices: [BluetoothDevice] = [],
        batteryLevels: [String: BluetoothBatteryLevel] = [:],
        batteryLevelsUpdatedAt: Date? = nil,
        selectedAirPodsAddress: String? = nil,
        selectedConnectedDeviceAddress: String? = nil,
        bluetoothAvailability: BluetoothAvailability? = nil,
        holdsAirPodsBattery: Bool = false,
        now: Date = .now
    ) -> IconSourceSnapshot {
        let networkAvailability: IconSourceAvailability
        if snapshot.connection == .ethernet {
            networkAvailability = .available
        } else {
            networkAvailability = switch snapshot.wifi.state {
            case .connected, .noInternet, .hotspot, .temporary, .shared:
                .available
            case .notAssociated, .off:
                .unavailable(.disconnected)
            case .unavailable:
                .unavailable(.unknown)
            }
        }
        let currentAudioOutputAvailability: IconSourceAvailability =
            snapshot.volume.currentDevice?.isBluetoothAudio == true
                ? .available
                : .unavailable(.disconnected)
        let volumeAvailability: IconSourceAvailability = snapshot.volume.scalar != nil
            ? .available
            : .unavailable(.unknown)
        // The numeric battery sources (centre percentage, footer) are hidden
        // without a battery, but the ring is not: #310 draws a battery-less Mac
        // as a full decorative ring, so its source stays available and the
        // mapper paints the 100% / full ring instead of falling back to nothing.
        let batteryAvailability: IconSourceAvailability = snapshot.battery.isPresent
            ? .available
            : .unavailable(.disconnected)

        let airPodsSelection = AirPodsBatteryIconSnapshot.selection(
            devices: bluetoothDevices,
            levels: batteryLevels,
            selectedAddress: selectedAirPodsAddress,
            observedAt: batteryLevelsUpdatedAt ?? .distantPast
        )
        let airPodsBattery: AirPodsBatteryIconSnapshot?
        let airPodsAvailability: IconSourceAvailability
        switch airPodsSelection {
        case let .selected(value):
            let age = now.timeIntervalSince(value.observedAt)
            let isFresh = (0...AirPodsBatteryIconSnapshot.freshnessInterval).contains(age)
            // While the icon holds the AirPods battery (it is the ring source),
            // keep the last reading on screen past the freshness window instead
            // of dropping to the fallback ring. The background claim keeps the
            // reading current; the hold only stops a quiet interval from
            // flickering the level away.
            let isUsable = isFresh || holdsAirPodsBattery
            airPodsBattery = isUsable ? value : nil
            airPodsAvailability = isUsable ? .available : .unavailable(.temporarilyStale)
        case .needsSelection:
            airPodsBattery = nil
            airPodsAvailability = .unavailable(.unknown)
        case let .unavailable(reason):
            airPodsBattery = nil
            airPodsAvailability = .unavailable(reason)
        }

        let selectedConnectedKey = selectedConnectedDeviceAddress.map { BluetoothBatteryReader.normalizedAddress($0) }
        let bluetoothDirectoryIsAuthoritative = bluetoothAvailability == nil || bluetoothAvailability == .available
        let connectedDevice = bluetoothDirectoryIsAuthoritative
            ? selectedConnectedKey.flatMap { selectedKey in
                bluetoothDevices.first {
                    BluetoothBatteryReader.normalizedAddress($0.id) == selectedKey
                        && $0.isConnected && !$0.isUnpairedGhost && !$0.isReadOverTheAir
                }
            }
            : nil
        let connectedDeviceSymbol = connectedDevice.map { BluetoothDeviceRowIcon.symbolName(for: $0) }
        let connectedDeviceIsAudio = connectedDevice.map { $0.kind.isAudio }
        let connectedDeviceAvailability: IconSourceAvailability
        if connectedDevice != nil {
            connectedDeviceAvailability = .available
        } else if selectedConnectedDeviceAddress == nil {
            connectedDeviceAvailability = .unavailable(.unknown)
        } else {
            let reason: IconSourceUnavailableReason = switch bluetoothAvailability {
            case .authorizationDenied, .authorizationRestricted:
                .permissionDenied
            case .poweredOff:
                .disconnected
            case .unavailable, .failed:
                .unavailable
            case .idle, .initializing, .authorizationNotDetermined:
                .unknown
            case .available, nil:
                .disconnected
            }
            connectedDeviceAvailability = .unavailable(reason)
        }

        return IconSourceSnapshot(availability: [
            CenterSource.network.rawValue: networkAvailability,
            CenterSource.bluetoothAudioOutput.rawValue: currentAudioOutputAvailability,
            CenterSource.systemBatteryPercentage.rawValue: batteryAvailability,
            CenterSource.connectedBluetoothDevice.rawValue: connectedDeviceAvailability,
            RingSource.systemBattery.rawValue: .available,
            RingSource.airPodsBattery.rawValue: airPodsAvailability,
            FooterSource.systemVolume.rawValue: volumeAvailability
        ], airPodsBattery: airPodsBattery, connectedBluetoothDeviceSymbol: connectedDeviceSymbol,
           connectedBluetoothDeviceIsAudio: connectedDeviceIsAudio,
           holdingSourceIDs: holdsAirPodsBattery ? [RingSource.airPodsBattery.rawValue] : [])
    }
}
