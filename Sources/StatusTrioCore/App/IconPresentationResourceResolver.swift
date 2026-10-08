import AppKit
import Foundation

@MainActor
enum IconPresentationResourceResolver {
    static func sourceSnapshot(snapshot: StatusSnapshot) -> IconSourceSnapshot {
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
        let bluetoothAvailability: IconSourceAvailability =
            snapshot.volume.currentDevice?.isBluetoothAudio == true
                ? .available
                : .unavailable(.disconnected)
        let volumeAvailability: IconSourceAvailability = snapshot.volume.scalar != nil
            ? .available
            : .unavailable(.unknown)
        let batteryAvailability: IconSourceAvailability = snapshot.battery.isPresent
            ? .available
            : .unavailable(.disconnected)

        return IconSourceSnapshot(availability: [
            CenterSource.network.rawValue: networkAvailability,
            CenterSource.bluetoothAudioOutput.rawValue: bluetoothAvailability,
            CenterSource.systemBatteryPercentage.rawValue: batteryAvailability,
            RingSource.systemBattery.rawValue: batteryAvailability,
            RingSource.airPodsBattery.rawValue: .unavailable(.unavailable),
            FooterSource.systemVolume.rawValue: volumeAvailability
        ])
    }

    static func inputs(
        snapshot: StatusSnapshot,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        isSymbolAvailable: (String) -> Bool = { symbol in
            NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil
        }
    ) -> IconPresentationInputs {
        guard let device = snapshot.volume.currentDevice else {
            return IconPresentationInputs(snapshot: snapshot, audioIcon: nil)
        }

        let source: IconSymbolSource
        if let iconURL = device.iconURL, fileExists(iconURL) {
            source = .image(url: iconURL, fallbackSymbol: "headphones")
        } else {
            let kind = AudioOutputDeviceIcon.kind(for: device)
            let host = HostMacKind(deviceName: device.name)
            let symbol = AudioOutputDeviceIcon.symbolName(for: kind, host: host, isSymbolAvailable: isSymbolAvailable)
            source = .symbol(name: symbol, variableValue: nil, fallback: "headphones")
        }
        return IconPresentationInputs(snapshot: snapshot, audioIcon: source)
    }
}
