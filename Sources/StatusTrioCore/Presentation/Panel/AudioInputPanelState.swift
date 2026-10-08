import Foundation

/// Opaque selected-device identity used only to detect an input switch.
/// It intentionally excludes UID, name, and presentation metadata.
struct PanelAudioInputIdentity: Equatable, Hashable, Sendable {
    private let value: UInt32

    init(rawValue: UInt32) {
        value = rawValue
    }
}

struct AudioInputPanelState: Equatable, Sendable {
    let summary: PanelSummaryState
    let selectedDeviceIdentity: PanelAudioInputIdentity?
    let scalar: Double?
    let percentageText: String
    let muteSymbol: String
    let muteTint: PanelTint
    let muteHelp: String
    let muteState: AudioInputMuteState?
    let canAdjust: Bool
    let canMute: Bool
    let isBusy: Bool
    let errorText: String?
    let showsDeviceList: Bool
    let rows: [PanelAudioDeviceRow]
    let sliderLabel: String
    let usageText: String?
}
