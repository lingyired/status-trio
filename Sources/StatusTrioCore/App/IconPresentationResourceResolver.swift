import AppKit
import Foundation

@MainActor
enum IconPresentationResourceResolver {
    static let availableBluetoothAudioIconChoices = BluetoothAudioIconChoice.availableChoices(
        isSymbolAvailable: { symbol in
            NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil
        }
    )

    static func inputs(
        snapshot: StatusSnapshot,
        inputSource: InputSourceDescriptor? = nil,
        systemPower: SystemPowerSample? = nil,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        isSymbolAvailable: (String) -> Bool = { symbol in
            NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil
        }
    ) -> IconPresentationInputs {
        let resolvedInputSource = inputSource?.resolvedForDrawing(fileExists: fileExists)
        guard let device = snapshot.volume.currentDevice else {
            return IconPresentationInputs(
                snapshot: snapshot,
                audioIcon: nil,
                inputSource: resolvedInputSource,
                systemPower: systemPower
            )
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
        return IconPresentationInputs(
            snapshot: snapshot,
            audioIcon: source,
            inputSource: resolvedInputSource,
            systemPower: systemPower
        )
    }
}
