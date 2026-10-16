import Foundation

/// What the icon-source menu offers: the featured audio-device entry, or one
/// picked device by its normalized address.
///
/// The picker binds through this value rather than the raw `String?` so the
/// menu can tag every row distinctly — `nil` cannot be a tag on its own —
/// while the store keeps the flat address form.
enum BluetoothNetworkIconSource: Hashable, Identifiable {
    case audioDevices
    case device(address: String)

    /// The glyph the audio entry draws and the row falls back to. Apple's
    /// AirPods symbol is the one macOS itself uses for a Bluetooth audio
    /// output, and it ships on every release the app supports.
    static let audioDeviceSymbol = "airpodspro"

    static func shouldShowAudioIconChoice(
        replacingNetworkIcon: Bool,
        selectedSource: Self
    ) -> Bool {
        replacingNetworkIcon && selectedSource == .audioDevices
    }

    var id: String {
        switch self {
        case .audioDevices:
            ""
        case let .device(address):
            address
        }
    }
}
