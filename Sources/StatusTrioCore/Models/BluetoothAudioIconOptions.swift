import Foundation

struct BluetoothAudioIconOptions: Equatable, Hashable, Sendable {
    static let defaultSymbolScale: Double = 1.6

    /// Whether the centre Bluetooth glyph uses the Bluetooth status colour.
    /// Off draws it in `.primary`, so it follows the menu bar's light/dark
    /// appearance instead of staying blue (#275). Independent of
    /// `usesVolumeColor`, which tints the volume footer.
    let usesIconColor: Bool
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
        usesIconColor: true,
        usesVolumeColor: false,
        symbolScale: defaultSymbolScale
    )

    init(
        usesIconColor: Bool = true,
        usesVolumeColor: Bool = false,
        symbolScale: Double = Self.defaultSymbolScale,
        networkIconSymbolOverride: String? = nil,
        iconChoice: BluetoothAudioIconChoice = .automatic
    ) {
        self.usesIconColor = usesIconColor
        self.usesVolumeColor = usesVolumeColor
        self.symbolScale = symbolScale
        self.networkIconSymbolOverride = networkIconSymbolOverride
        self.iconChoice = iconChoice
    }
}
