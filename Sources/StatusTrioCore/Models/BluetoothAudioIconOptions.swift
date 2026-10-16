import Foundation

struct BluetoothAudioIconOptions: Equatable, Hashable, Sendable {
    static let defaultSymbolScale: Double = 1.6

    let replacesNetworkIcon: Bool
    let usesVolumeColor: Bool
    let prioritizesNetworkErrors: Bool
    let symbolScale: Double
    /// The SF Symbol a picked Bluetooth device resolved to. When set, it — not
    /// the current audio output — is what replaces the network icon, and the
    /// current output no longer has to be Bluetooth or exist at all. `nil`
    /// keeps the original behavior: the current Bluetooth audio output draws.
    let networkIconSymbolOverride: String?
    /// A global choice used only while the current output is Bluetooth audio.
    let iconChoice: BluetoothAudioIconChoice

    static let standard = BluetoothAudioIconOptions(
        replacesNetworkIcon: false,
        usesVolumeColor: false,
        prioritizesNetworkErrors: true,
        symbolScale: defaultSymbolScale
    )

    init(
        replacesNetworkIcon: Bool = false,
        usesVolumeColor: Bool = false,
        prioritizesNetworkErrors: Bool = true,
        symbolScale: Double = Self.defaultSymbolScale,
        networkIconSymbolOverride: String? = nil,
        iconChoice: BluetoothAudioIconChoice = .automatic
    ) {
        self.replacesNetworkIcon = replacesNetworkIcon
        self.usesVolumeColor = usesVolumeColor
        self.prioritizesNetworkErrors = prioritizesNetworkErrors
        self.symbolScale = symbolScale
        self.networkIconSymbolOverride = networkIconSymbolOverride
        self.iconChoice = iconChoice
    }
}
