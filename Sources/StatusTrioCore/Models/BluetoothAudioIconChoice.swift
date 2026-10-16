import Foundation

/// A stable user-selected SF Symbol for the Bluetooth audio connection icon.
/// Raw values intentionally match the system symbol names so preferences stay
/// readable across releases; `automatic` always follows the active device.
enum BluetoothAudioIconChoice: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case earbuds
    case overEarHeadphones = "headphones.over.ear"
    case headset
    case earpods
    case headphones
    case airpods
    case airpodsGen3 = "airpods.gen3"
    case airpodsGen4 = "airpods.gen4"
    case airpodsPro = "airpods.pro"
    case airpodsProGen1 = "airpods.pro.gen1"
    case airpodsProGen3 = "airpods.pro.gen3"
    case airpodsMax = "airpodsmax"
    case beatsPill = "beats.pill"
    case beatsSoloBuds = "beats.solobuds"
    case beatsStudioBudsPlus = "beats.studiobuds.plus"
    case beatsStudioBuds = "beats.studiobuds"
    case beatsFitPro = "beats.fit.pro"
    case beatsPowerbeatsPro2 = "beats.powerbeats.pro.2"
    case beatsPowerbeatsPro = "beats.powerbeatspro"
    case beatsPowerbeats3 = "beats.powerbeats3"
    case beatsPowerbeats = "beats.powerbeats"
    case beatsEarphones = "beats.earphones"
    case beatsHeadphones = "beats.headphones"
    case homePod = "homepod"
    case homePodMini = "homepod.mini"
    case homePod2 = "homepod.2"
    case homePodMini2 = "homepodmini.2"
    case hiFiSpeaker = "hifispeaker"
    case hiFiSpeaker2 = "hifispeaker.2"
    case speakerWave2 = "speaker.wave.2"

    var id: String { rawValue }
    var symbolName: String? { self == .automatic ? nil : rawValue }

    /// Filters symbols using AppKit's system-symbol lookup on the running OS.
    /// This naturally omits symbols unavailable on macOS 15 and preserves the
    /// stable stored choice for a later OS that supports it.
    @MainActor
    static func availableChoices(isSymbolAvailable: @MainActor (String) -> Bool) -> [Self] {
        allCases.filter { choice in
            guard let symbolName = choice.symbolName else { return true }
            return isSymbolAvailable(symbolName)
        }
    }

    /// Unknown or unsupported persisted selections behave as Automatic without
    /// rewriting the preference, so an OS upgrade can restore the selection.
    @MainActor
    static func persisted(
        _ rawValue: String?,
        isSymbolAvailable: @MainActor (String) -> Bool
    ) -> Self {
        guard let rawValue, let choice = Self(rawValue: rawValue) else { return .automatic }
        guard let symbolName = choice.symbolName else { return choice }
        return isSymbolAvailable(symbolName) ? choice : .automatic
    }

    var localizationKey: LocalizationKey? {
        switch self {
        case .automatic: .settingsBluetoothIconChoiceAutomatic
        case .earbuds: .settingsBluetoothIconChoiceEarbuds
        case .overEarHeadphones: .settingsBluetoothIconChoiceOverEar
        case .headset: .settingsBluetoothIconChoiceHeadset
        case .earpods: .settingsBluetoothIconChoiceEarPods
        case .headphones: .settingsBluetoothIconChoiceHeadphones
        default: nil
        }
    }

    var productName: String {
        switch self {
        case .automatic: ""
        case .earbuds: "Earbuds"
        case .overEarHeadphones: "Over-Ear Headphones"
        case .headset: "Headset"
        case .earpods: "EarPods"
        case .headphones: "Headphones"
        case .airpods: "AirPods"
        case .airpodsGen3: "AirPods 3"
        case .airpodsGen4: "AirPods 4"
        case .airpodsPro: "AirPods Pro"
        case .airpodsProGen1: "AirPods Pro 1"
        case .airpodsProGen3: "AirPods Pro 3"
        case .airpodsMax: "AirPods Max"
        case .beatsPill: "Beats Pill"
        case .beatsSoloBuds: "Beats Solo Buds"
        case .beatsStudioBudsPlus: "Beats Studio Buds +"
        case .beatsStudioBuds: "Beats Studio Buds"
        case .beatsFitPro: "Beats Fit Pro"
        case .beatsPowerbeatsPro2: "Beats Powerbeats Pro 2"
        case .beatsPowerbeatsPro: "Beats Powerbeats Pro"
        case .beatsPowerbeats3: "Beats Powerbeats 3"
        case .beatsPowerbeats: "Beats Powerbeats"
        case .beatsEarphones: "Beats Earphones"
        case .beatsHeadphones: "Beats Headphones"
        case .homePod: "HomePod"
        case .homePodMini: "HomePod mini"
        case .homePod2: "HomePod"
        case .homePodMini2: "HomePod mini"
        case .hiFiSpeaker: "Hi-Fi Speaker"
        case .hiFiSpeaker2: "Hi-Fi Speaker"
        case .speakerWave2: "Speaker"
        }
    }

    @MainActor
    func displayName(using localization: Localization) -> String {
        if let localizationKey { return localization.string(localizationKey) }
        return switch self {
        case .hiFiSpeaker: localization.string(.settingsBluetoothIconChoiceHiFiSpeaker)
        case .homePod2:
            "HomePod (\(localization.string(.settingsBluetoothIconChoiceStereoPair)))"
        case .homePodMini2:
            "HomePod mini (\(localization.string(.settingsBluetoothIconChoiceStereoPair)))"
        case .hiFiSpeaker2:
            "\(localization.string(.settingsBluetoothIconChoiceHiFiSpeaker)) (\(localization.string(.settingsBluetoothIconChoiceStereoPair)))"
        case .speakerWave2: localization.string(.settingsBluetoothIconChoiceSpeaker)
        default: productName
        }
    }
}
