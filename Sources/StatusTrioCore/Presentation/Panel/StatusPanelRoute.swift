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

/// Where a selected detail page appears while the status panel is open.
enum StatusPanelDetailPresentation: Equatable, Sendable {
    /// The detail replaces the summary inside the status panel window.
    case inline
    /// The detail opens in an attached panel beside the summary.
    case alongside
}
