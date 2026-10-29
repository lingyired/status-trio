enum StatusPanelRoute: Equatable, Sendable {
    case summary
    case battery
    case wifi
    case ethernet
    case inputSource
}

struct WiFiPanelDisclosureState: Equatable, Sendable {
    var showsDetails = false
    var showsMore = false
}
