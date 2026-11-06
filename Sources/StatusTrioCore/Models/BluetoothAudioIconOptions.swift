import Foundation

struct BluetoothAudioIconOptions: Equatable, Hashable, Sendable {
    static let defaultSymbolScale: Double = 1.6

    /// The colour of the centre Bluetooth glyph: default blue, system primary,
    /// or a user-picked colour (#275). Independent of `usesVolumeColor`, which
    /// tints the volume footer.
    let iconColor: BluetoothIconColorSelection
    let usesVolumeColor: Bool
    let symbolScale: Double
    /// The SF Symbol a picked Bluetooth device resolved to. When set, it — not
    /// the current audio output — is what replaces the network icon, and the
    /// current output no longer has to be Bluetooth or exist at all. `nil`
    /// keeps the original behavior: the current Bluetooth audio output draws.
    let networkIconSymbolOverride: String?
    /// A global choice used only while the current output is Bluetooth audio.
    let iconChoice: BluetoothAudioIconChoice

    static let standard = BluetoothAudioIconOptions(
        iconColor: .default,
        usesVolumeColor: false,
        symbolScale: defaultSymbolScale
    )

    init(
        iconColor: BluetoothIconColorSelection = .default,
        usesVolumeColor: Bool = false,
        symbolScale: Double = Self.defaultSymbolScale,
        networkIconSymbolOverride: String? = nil,
        iconChoice: BluetoothAudioIconChoice = .automatic
    ) {
        self.iconColor = iconColor
        self.usesVolumeColor = usesVolumeColor
        self.symbolScale = symbolScale
        self.networkIconSymbolOverride = networkIconSymbolOverride
        self.iconChoice = iconChoice
    }
}
