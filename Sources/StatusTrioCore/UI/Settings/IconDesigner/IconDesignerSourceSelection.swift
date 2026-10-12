import Foundation

enum IconDesignerCenterChoice: CaseIterable, Equatable, Sendable {
    case network
    case bluetoothDevice
    case macBatteryPercentage
    case none
}

enum IconDesignerSourceSelection {
    static let centerChoices: [IconDesignerCenterChoice] = [
        .network, .bluetoothDevice, .macBatteryPercentage, .none
    ]

    static func choice(for source: CenterSource) -> IconDesignerCenterChoice? {
        switch source {
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
        case .network: .network
        case .bluetoothDevice: .bluetoothAudioOutput
        case .macBatteryPercentage: .systemBatteryPercentage
        case .none: .none
        }
    }
}
