import Foundation

enum IconDesignerSource: Hashable, Identifiable {
    case ring(RingSource)
    case center(CenterSource)
    case footer(FooterSource)

    var id: String {
        switch self {
        case let .ring(source): "ring.\(source.rawValue)"
        case let .center(source): "center.\(source.rawValue)"
        case let .footer(source): "footer.\(source.rawValue)"
        }
    }

    var rawValue: String {
        switch self {
        case let .ring(source): source.rawValue
        case let .center(source): source.rawValue
        case let .footer(source): source.rawValue
        }
    }
}

struct IconDesignerCurrentSource: Equatable {
    let id: String
    let isSelectable: Bool
    let isLegacy: Bool
}

enum IconDesignerEditingModel {
    static func selectableSources(for slot: IconSlot, phaseFiveEnabled: Bool = false) -> [IconDesignerSource] {
        switch slot {
        case .outerRing:
            var sources: [IconDesignerSource] = [.ring(.automaticLegacy), .ring(.systemBattery), .ring(.none)]
            if phaseFiveEnabled { sources.insert(.ring(.airPodsBattery), at: 2) }
            return sources
        case .center:
            return [
                .center(.automaticLegacy), .center(.network), .center(.bluetoothAudioOutput),
                .center(.pinnedBluetoothGlyph), .center(.connectedBluetoothDevice),
                .center(.systemBatteryPercentage), .center(.none)
            ]
        case .footer:
            return [.footer(.systemVolume), .footer(.none)]
        }
    }

    static func currentSource(for slot: IconSlot, in configuration: IconConfigurationV1,
                              phaseFiveEnabled: Bool = false) -> IconDesignerCurrentSource {
        let selected: IconDesignerSource
        switch slot {
        case .outerRing: selected = .ring(configuration.composition.outerRing.primary)
        case .center: selected = .center(configuration.composition.center.primary)
        case .footer: selected = .footer(configuration.composition.footer.primary)
        }
        return IconDesignerCurrentSource(
            id: selected.rawValue,
            isSelectable: selectableSources(for: slot, phaseFiveEnabled: phaseFiveEnabled).contains(selected),
            isLegacy: selected.rawValue == "automaticLegacy"
        )
    }

    @discardableResult
    static func setPrimary(_ source: IconDesignerSource, for slot: IconSlot,
                           in configuration: inout IconConfigurationV1,
                           phaseFiveEnabled: Bool = false) -> Bool {
        guard selectableSources(for: slot, phaseFiveEnabled: phaseFiveEnabled).contains(source) else { return false }
        switch (slot, source) {
        case let (.outerRing, .ring(value)): configuration.composition.outerRing.primary = value
        case let (.center, .center(value)): configuration.composition.center.primary = value
        case let (.footer, .footer(value)): configuration.composition.footer.primary = value
        default: return false
        }
        configuration = configuration.normalized()
        return true
    }

    @discardableResult
    static func swapPrimaryAndFallback(for slot: IconSlot, in configuration: inout IconConfigurationV1) -> Bool {
        switch slot {
        case .outerRing:
            guard let fallback = configuration.composition.outerRing.fallback else { return false }
            configuration.composition.outerRing = SlotSelection(primary: fallback, fallback: configuration.composition.outerRing.primary)
        case .center:
            guard let fallback = configuration.composition.center.fallback else { return false }
            configuration.composition.center = SlotSelection(primary: fallback, fallback: configuration.composition.center.primary)
        case .footer:
            guard let fallback = configuration.composition.footer.fallback else { return false }
            configuration.composition.footer = SlotSelection(primary: fallback, fallback: configuration.composition.footer.primary)
        }
        configuration = configuration.normalized()
        return true
    }

    @discardableResult
    static func setFallback(_ source: IconDesignerSource?, for slot: IconSlot,
                            in configuration: inout IconConfigurationV1,
                            phaseFiveEnabled: Bool = false) -> Bool {
        if let source, !selectableSources(for: slot, phaseFiveEnabled: phaseFiveEnabled).contains(source) { return false }
        switch (slot, source) {
        case let (.outerRing, .ring(value)?):
            guard value != configuration.composition.outerRing.primary else { return false }
            configuration.composition.outerRing.fallback = value
        case let (.center, .center(value)?):
            guard value != configuration.composition.center.primary else { return false }
            configuration.composition.center.fallback = value
        case let (.footer, .footer(value)?):
            guard value != configuration.composition.footer.primary else { return false }
            configuration.composition.footer.fallback = value
        case (.outerRing, nil): configuration.composition.outerRing.fallback = nil
        case (.center, nil): configuration.composition.center.fallback = nil
        case (.footer, nil): configuration.composition.footer.fallback = nil
        default: return false
        }
        configuration = configuration.normalized()
        return true
    }

    @discardableResult
    static func setBluetoothSymbolOverride(_ symbol: String?, in configuration: inout IconConfigurationV1) -> Bool {
        guard configuration.composition.center.primary == .bluetoothAudioOutput else { return false }
        configuration.behaviors.bluetoothAudioCenter.networkIconSymbolOverride = symbol
        configuration = configuration.normalized()
        return true
    }

    static func allowsNetworkProblemOverride(in configuration: IconConfigurationV1) -> Bool {
        configuration.composition.center.primary == .bluetoothAudioOutput
    }
}
