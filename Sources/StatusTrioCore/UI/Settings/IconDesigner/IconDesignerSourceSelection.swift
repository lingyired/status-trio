import Foundation

enum IconDesignerCenterChoice: CaseIterable, Equatable, Sendable {
    case inputSource
    case network
    case bluetoothDevice
    case macBatteryPercentage
    case none
}

enum IconDesignerSourceSelection {
    static let centerChoices: [IconDesignerCenterChoice] = [
        .inputSource, .network, .bluetoothDevice, .macBatteryPercentage, .none
    ]

    static func choice(for source: CenterSource) -> IconDesignerCenterChoice? {
        switch source {
        case .inputSource:
            .inputSource
        case .network:
            .network
        case .bluetoothAudioOutput, .connectedBluetoothDevice:
            .bluetoothDevice
        case .systemBatteryPercentage:
            .macBatteryPercentage
        case .none:
            IconDesignerCenterChoice.none
        case .automaticLegacy, .pinnedBluetoothGlyph:
            nil
        }
    }

    static func source(for choice: IconDesignerCenterChoice) -> CenterSource {
        switch choice {
        case .inputSource: .inputSource
        case .network: .network
        case .bluetoothDevice: .bluetoothAudioOutput
        case .macBatteryPercentage: .systemBatteryPercentage
        case .none: .none
        }
    }

    /// Every displayable source's localized name, keyed by its raw source id.
    ///
    /// Both the slot selector's accessibility value and the source editor label
    /// read from here, so a newly added `CenterSource` cannot silently fall
    /// through to the "None" label on one surface while the picker shows the
    /// right name on the other. `nil` means the id is not a known source; the
    /// callers render that as None.
    static func localizationKey(forRawSourceID sourceID: String) -> LocalizationKey? {
        switch sourceID {
        case "automaticLegacy": .iconDesignerSourceLegacy
        case "systemBattery": .iconDesignerSourceSystemBattery
        case "airPodsBattery": .iconDesignerSourceAirPodsBattery
        case "network": .iconDesignerSourceNetwork
        case "inputSource": .iconDesignerSourceInputSource
        case "bluetoothAudioOutput": .iconDesignerSourceBluetoothAudio
        case "pinnedBluetoothGlyph": .iconDesignerSourcePinnedBluetooth
        case "connectedBluetoothDevice": .iconDesignerSourceConnectedBluetooth
        case "systemBatteryPercentage": .iconDesignerSourceBatteryPercentage
        case "systemVolume": .iconDesignerSourceSystemVolume
        case "none": .iconDesignerSourceNone
        default: nil
        }
    }
}
