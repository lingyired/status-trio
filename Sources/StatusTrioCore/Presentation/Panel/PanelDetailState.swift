import Foundation

struct PanelDetailRow: Equatable, Sendable {
    let id: String
    let label: String
    let value: String
    let accessibilityValue: String
    let tint: PanelTint
    let isCopyable: Bool

    init(
        id: String,
        label: String,
        value: String,
        accessibilityValue: String,
        tint: PanelTint,
        isCopyable: Bool = false
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.accessibilityValue = accessibilityValue
        self.tint = tint
        self.isCopyable = isCopyable
    }
}

struct PanelDetailState: Equatable, Sendable {
    let title: String
    let rows: [PanelDetailRow]
    let isLoading: Bool
    let errorText: String?
    let explanation: String?
    var lifecycleIdentity: String? = nil
}

struct PanelWiFiNetworkRow: Equatable, Sendable {
    let key: WiFiNetworkIdentity
    let name: String
    let signalSymbol: IconSymbolSource
    let signalSystemImage: String?
    let securityMarker: String?
    let selected: Bool
    let accessibilityLabel: String
    let opensSettings: Bool
}

struct WiFiPanelState: Equatable, Sendable {
    let detail: PanelDetailState
    let collapsedDetailRowCount: Int
    let showMoreTitle: String
    let showLessTitle: String
    let personalHotspotRows: [PanelWiFiNetworkRow]
    let knownRows: [PanelWiFiNetworkRow]
    let otherRows: [PanelWiFiNetworkRow]
    let powerIsOn: Bool
    let canSetPower: Bool
    let canRefresh: Bool
    let isScanning: Bool
    let message: String?
    let messageIntent: PanelSummaryIntent
    let showsConnectionDetails: Bool

    init(
        detail: PanelDetailState,
        collapsedDetailRowCount: Int = 9,
        showMoreTitle: String = "",
        showLessTitle: String = "",
        personalHotspotRows: [PanelWiFiNetworkRow] = [],
        knownRows: [PanelWiFiNetworkRow],
        otherRows: [PanelWiFiNetworkRow],
        powerIsOn: Bool,
        canSetPower: Bool,
        canRefresh: Bool,
        isScanning: Bool,
        message: String?,
        messageIntent: PanelSummaryIntent,
        showsConnectionDetails: Bool = false
    ) {
        self.detail = detail
        self.collapsedDetailRowCount = collapsedDetailRowCount
        self.showMoreTitle = showMoreTitle
        self.showLessTitle = showLessTitle
        self.personalHotspotRows = personalHotspotRows
        self.knownRows = knownRows
        self.otherRows = otherRows
        self.powerIsOn = powerIsOn
        self.canSetPower = canSetPower
        self.canRefresh = canRefresh
        self.isScanning = isScanning
        self.message = message
        self.messageIntent = messageIntent
        self.showsConnectionDetails = showsConnectionDetails
    }

    func visibleDetailRows(expanded: Bool) -> [PanelDetailRow] {
        Array(detail.rows.prefix(expanded ? detail.rows.count : collapsedDetailRowCount))
    }
}
