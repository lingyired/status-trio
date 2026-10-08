import Foundation

struct PanelAudioDeviceID: Equatable, Hashable, Sendable {
    let id: UInt32
    let uid: String?
}

struct PanelAudioDeviceRow: Equatable, Identifiable, Sendable {
    let key: PanelAudioDeviceID
    let name: String
    let symbol: IconSymbolSource
    let selected: Bool
    let enabled: Bool
    let accessibilityLabel: String
    var helpText: String = ""
    var volumeText: String? = nil
    var listeningModeAddress: String? = nil
    var listeningMode: BluetoothListeningModePresentation? = nil
    var isPreview: Bool = false

    var id: PanelAudioDeviceID { key }
}

struct AudioOutputListPreferences: Equatable, Sendable {
    let order: [String]
    let visibleLimit: Int?

    init(order: [String] = [], visibleLimit: Int? = 5) {
        self.order = order
        self.visibleLimit = visibleLimit.map { max(0, $0) }
    }

    static let `default` = Self()
}

struct VolumePanelState: Equatable, Sendable {
    let summary: PanelSummaryState
    let scalar: Double?
    let percentageText: String
    let muted: Bool
    let canAdjust: Bool
    let canMute: Bool
    let muteSymbol: String
    let muteHelp: String
    let sliderLabel: String
    let showsDeviceList: Bool
    /// Complete rows stay resolved in display order. The view owns only whether
    /// its local disclosure is expanded.
    let rows: [PanelAudioDeviceRow]
    let previewRows: [PanelAudioDeviceRow]
    let visibleLimit: Int?
    let expandLabel: String
    let collapseLabel: String
    let listeningModeTaskID: String
    let previewLanguageCode: String

    var hasHiddenRows: Bool {
        OutputDeviceListPresentation.canToggleExpansion(for: rows, limit: visibleLimit)
    }

    func visibleRows(expanded: Bool) -> [PanelAudioDeviceRow] {
        OutputDeviceListPresentation.visibleDevices(
            from: rows,
            limit: visibleLimit,
            isExpanded: expanded
        )
    }
}
