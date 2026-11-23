struct ConnectionIconOptions: Equatable, Hashable, Sendable {
    let showsWiFiIconForEthernet: Bool
    let showsWiFiIconForHotspot: Bool
    let showsWiFiIconForTemporaryConnection: Bool
    let showsWiFiIconForInternetSharing: Bool
    /// What the centre slot draws; each choice owns the slot exclusively.
    let centerSource: ConnectionCenterSource
    /// A genuine network outage overrides any selected content source.
    /// Defaults to on so the centre slot stays honest about a dead link.
    let prioritizesNetworkErrors: Bool
    let wifiScale: Double

    static let standard = ConnectionIconOptions(
        showsWiFiIconForEthernet: false,
        showsWiFiIconForHotspot: false,
        showsWiFiIconForTemporaryConnection: false,
        showsWiFiIconForInternetSharing: false,
        centerSource: .network,
        prioritizesNetworkErrors: true,
        wifiScale: 1.0
    )

    init(
        showsWiFiIconForEthernet: Bool = false,
        showsWiFiIconForHotspot: Bool = false,
        showsWiFiIconForTemporaryConnection: Bool = false,
        showsWiFiIconForInternetSharing: Bool = false,
        centerSource: ConnectionCenterSource = .network,
        prioritizesNetworkErrors: Bool = true,
        wifiScale: Double = 1.0
    ) {
        self.showsWiFiIconForEthernet = showsWiFiIconForEthernet
        self.showsWiFiIconForHotspot = showsWiFiIconForHotspot
        self.showsWiFiIconForTemporaryConnection = showsWiFiIconForTemporaryConnection
        self.showsWiFiIconForInternetSharing = showsWiFiIconForInternetSharing
        self.centerSource = centerSource
        self.prioritizesNetworkErrors = prioritizesNetworkErrors
        self.wifiScale = wifiScale
    }
}
