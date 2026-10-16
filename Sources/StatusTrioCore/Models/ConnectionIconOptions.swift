struct ConnectionIconOptions: Equatable, Hashable, Sendable {
    let showsWiFiIconForEthernet: Bool
    let showsWiFiIconForHotspot: Bool
    let showsWiFiIconForTemporaryConnection: Bool
    let showsWiFiIconForInternetSharing: Bool
    let showsBatteryPercentageInConnectionSlot: Bool
    /// Which of the two centre-slot sources the user chose. `.automatic` keeps
    /// every shipped priority rule untouched.
    let centerSource: ConnectionCenterSource
    /// While an input source is drawn, show a genuine network outage instead.
    /// Defaults to on so the centre slot stays honest about a dead link.
    let prioritizesNetworkErrorsOverInputSource: Bool
    let wifiScale: Double

    static let standard = ConnectionIconOptions(
        showsWiFiIconForEthernet: false,
        showsWiFiIconForHotspot: false,
        showsWiFiIconForTemporaryConnection: false,
        showsWiFiIconForInternetSharing: false,
        showsBatteryPercentageInConnectionSlot: false,
        centerSource: .automatic,
        prioritizesNetworkErrorsOverInputSource: true,
        wifiScale: 1.0
    )

    init(
        showsWiFiIconForEthernet: Bool = false,
        showsWiFiIconForHotspot: Bool = false,
        showsWiFiIconForTemporaryConnection: Bool = false,
        showsWiFiIconForInternetSharing: Bool = false,
        showsBatteryPercentageInConnectionSlot: Bool = false,
        centerSource: ConnectionCenterSource = .automatic,
        prioritizesNetworkErrorsOverInputSource: Bool = true,
        wifiScale: Double = 1.0
    ) {
        self.showsWiFiIconForEthernet = showsWiFiIconForEthernet
        self.showsWiFiIconForHotspot = showsWiFiIconForHotspot
        self.showsWiFiIconForTemporaryConnection = showsWiFiIconForTemporaryConnection
        self.showsWiFiIconForInternetSharing = showsWiFiIconForInternetSharing
        self.showsBatteryPercentageInConnectionSlot = showsBatteryPercentageInConnectionSlot
        self.centerSource = centerSource
        self.prioritizesNetworkErrorsOverInputSource = prioritizesNetworkErrorsOverInputSource
        self.wifiScale = wifiScale
    }
}
