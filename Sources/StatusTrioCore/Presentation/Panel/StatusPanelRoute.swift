enum StatusPanelRoute: Equatable, Sendable {
    case summary
    case battery
    case wifi
    case ethernet
    case inputSource
    /// A unified system-monitor detail page (CPU/GPU/RAM/Network/Disk).
    case hardwareDetail(HardwareDetailKind)
}

struct WiFiPanelDisclosureState: Equatable, Sendable {
    var showsDetails = false
    var showsMore = false
}
