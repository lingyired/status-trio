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

enum IconDesignerBehaviorTarget: String, CaseIterable, Hashable, Sendable {
    case primary
    case fallback
}

enum IconDesignerEditingModel {

    static var wifiScaleForCommonPercentageSize: Double {
        CenterPercentageScaleCalibration.wifiScaleForCommonPercentageSize
    }

    static var commonPercentageScaleRange: ClosedRange<Double> {
        IconCenterSizingPolicy.percentageRange
    }

    @MainActor
    static var batteryTextScaleRange: ClosedRange<Double> {
        SettingsStore.batterySymbolScaleRange
    }

    @MainActor
    static func batteryTextScaleSliderValue(for rawTextScale: Double) -> Double {
        guard rawTextScale.isFinite else { return SettingsStore.defaultBatterySymbolScale }
        return min(batteryTextScaleRange.upperBound, max(
            batteryTextScaleRange.lowerBound,
            rawTextScale / BatteryIconOptions.defaultTextScale
        ))
    }

    static func batteryTextScaleLabel(for rawTextScale: Double) -> String {
        guard rawTextScale.isFinite else { return "100%" }
        return String(format: "%.0f%%", rawTextScale / BatteryIconOptions.defaultTextScale * 100)
    }

    @MainActor
    static func batteryTextScale(forSliderValue value: Double) -> Double {
        SettingsStore.clampedBatterySymbolScale(value) * BatteryIconOptions.defaultTextScale
    }

    @MainActor
    static func settingBatteryTextScale(_ sliderValue: Double, in configuration: inout IconConfigurationV1) {
        guard sliderValue.isFinite else { return }
        configuration.behaviors.systemBatteryRing.textScale = batteryTextScale(forSliderValue: sliderValue)
    }

    static func effectiveCenterScale(for source: CenterSource, in configuration: IconConfigurationV1) -> Double {
        if let explicit = configuration.appearance.center.effectiveSymbolScale { return explicit }
        let legacyAppearanceFactor = configuration.appearance.center.symbolScale / CenterAppearance.classic.symbolScale
        switch source {
        case .systemBatteryPercentage:
            return min(6, max(0.5, configuration.behaviors.systemBatteryRing.textScale * legacyAppearanceFactor))
        case .network, .inputSource:
            return min(6, max(0.5, configuration.legacyPresentationConfiguration.connection.wifiScale * legacyAppearanceFactor))
        case .bluetoothAudioOutput, .connectedBluetoothDevice, .pinnedBluetoothGlyph:
            return min(6, max(0.5, configuration.behaviors.bluetoothAudioCenter.symbolScale * legacyAppearanceFactor))
        case .automaticLegacy, .none:
            return configuration.appearance.center.symbolScale / CenterAppearance.classic.symbolScale
        }
    }

    static func effectiveCenterScale(in configuration: IconConfigurationV1) -> Double {
        if let explicit = configuration.appearance.center.effectiveSymbolScale { return explicit }
        return effectiveCenterScale(for: configuration.composition.center.primary, in: configuration)
    }

    static func commonPercentageScale(for source: CenterSource, in configuration: IconConfigurationV1) -> Double {
        if let normalized = configuration.appearance.center.normalizedSizePercentage { return normalized }
        let legacyScale = effectiveCenterScale(for: source, in: configuration)
        switch source {
        case .network, .inputSource:
            if let legacyPercentage = configuration.appearance.center.normalizedPercentageScale { return legacyPercentage }
            return legacyScale / wifiScaleForCommonPercentageSize
        case .systemBatteryPercentage:
            if let legacyPercentage = configuration.appearance.center.normalizedPercentageScale { return legacyPercentage }
            return legacyScale / CenterPercentageScaleCalibration.percentageScaleForCommonSize
        default:
            return legacyScale
        }
    }

    static func commonPercentageScale(in configuration: IconConfigurationV1) -> Double {
        let source = configuration.composition.center.primary
        if source == .none { return configuration.appearance.center.normalizedSizePercentage ?? 1 }
        return commonPercentageScale(for: source, in: configuration)
    }

    static func commonPercentageScaleLabel(for value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    static func commonPercentageScaleSliderValue(for value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(commonPercentageScaleRange.upperBound, max(commonPercentageScaleRange.lowerBound, value))
    }

    static func settingCommonPercentageScale(_ value: Double, in configuration: inout IconConfigurationV1) {
        guard value.isFinite else { return }
        // Keep historical fields intact for rollback/decoding. This field takes over only after an explicit edit.
        configuration.appearance.center.normalizedSizePercentage = IconCenterSizingPolicy.normalizedPercentage(value)
    }

    static func settingEffectiveCenterScale(_ value: Double, in configuration: inout IconConfigurationV1) {
        guard value.isFinite else { return }
        configuration.appearance.center.effectiveSymbolScale = min(6, max(0.5, value))
    }

    static func supportsImplementedSources(for slot: IconSlot) -> Bool {
        slot == .outerRing || slot == .center
    }

    static func requiresConnectedBluetoothDevice(in configuration: IconConfigurationV1) -> Bool {
        let selection = configuration.composition.center
        return selection.primary == .connectedBluetoothDevice || selection.fallback == .connectedBluetoothDevice
    }

    static func requiresAirPodsBattery(in configuration: IconConfigurationV1) -> Bool {
        configuration.composition.outerRing.primary == .airPodsBattery
            || configuration.composition.outerRing.fallback == .airPodsBattery
    }

    static func requiresInputSource(in configuration: IconConfigurationV1) -> Bool {
        let selection = configuration.composition.center
        return selection.primary == .inputSource || selection.fallback == .inputSource
    }

    static func applyingAirPodsFocus(to configuration: IconConfigurationV1) -> IconConfigurationV1 {
        var copy = configuration
        copy.composition.outerRing = SlotSelection(primary: .airPodsBattery, fallback: .systemBattery)
        copy.behaviors.airPodsRing = .dual
        return copy.normalized()
    }

    static func behaviorTargets(for slot: IconSlot, in configuration: IconConfigurationV1) -> [IconDesignerBehaviorTarget] {
        let fallbackExists: Bool = switch slot {
        case .outerRing: configuration.composition.outerRing.fallback != nil
        case .center: configuration.composition.center.fallback != nil
        case .footer: configuration.composition.footer.fallback != nil
        }
        return fallbackExists ? [.primary, .fallback] : [.primary]
    }

    static func validatedBehaviorTarget(
        _ target: IconDesignerBehaviorTarget,
        slot: IconSlot,
        in configuration: IconConfigurationV1
    ) -> IconDesignerBehaviorTarget {
        behaviorTargets(for: slot, in: configuration).contains(target) ? target : .primary
    }

    static func effectiveBehaviorTarget(
        _ target: IconDesignerBehaviorTarget,
        slot: IconSlot,
        in configuration: IconConfigurationV1
    ) -> IconDesignerBehaviorTarget {
        validatedBehaviorTarget(target, slot: slot, in: configuration)
    }

    static func source(for target: IconDesignerBehaviorTarget, slot: IconSlot, in configuration: IconConfigurationV1) -> IconDesignerSource? {
        switch (slot, target) {
        case (.outerRing, .primary): .ring(configuration.composition.outerRing.primary)
        case (.outerRing, .fallback): configuration.composition.outerRing.fallback.map(IconDesignerSource.ring)
        case (.center, .primary): .center(configuration.composition.center.primary)
        case (.center, .fallback): configuration.composition.center.fallback.map(IconDesignerSource.center)
        case (.footer, .primary): .footer(configuration.composition.footer.primary)
        case (.footer, .fallback): configuration.composition.footer.fallback.map(IconDesignerSource.footer)
        }
    }

    static func behaviors(
        for slot: IconSlot,
        source: IconDesignerSource,
        bluetoothTarget: IconDesignerBluetoothTarget,
        devices: [BluetoothDevice]
    ) -> Set<IconDesignerBehaviorCapability> {
        guard let binding = source.pluginBinding else { return [] }
        return BuiltinIconPlugins.makeRegistry().capabilities(for: binding,
            context: .init(configuration: .classic,
                targetIsAudio: IconDesignerBluetoothTargetModel.isAudioTarget(bluetoothTarget, devices: devices)))
    }

    static func behaviors(for slot: IconSlot, source: IconDesignerSource) -> Set<IconDesignerBehaviorCapability> {
        guard let binding = source.pluginBinding else { return [] }
        return BuiltinIconPlugins.makeRegistry().capabilities(for: binding,
            context: .init(configuration: .classic, targetIsAudio: false))
    }

    static func selectableSources(for slot: IconSlot, phaseFiveEnabled: Bool = true,
                                  registry: IconContentPluginRegistry = BuiltinIconPlugins.makeRegistry()) -> [IconDesignerSource] {
        var result: [IconDesignerSource] = []
        for option in registry.presentations(for: slot) {
            let source: IconDesignerSource?
            switch slot {
            case .outerRing: source = IconContentLegacyAdapter.ringSource(for: option.binding).map { .ring($0) }
            case .center: source = IconContentLegacyAdapter.centerSource(for: option.binding).map {
                .center(IconDesignerBluetoothTargetModel.displaySource(for: $0))
            }
            case .footer: source = IconContentLegacyAdapter.footerSource(for: option.binding).map { .footer($0) }
            }
            if let source, !result.contains(source) { result.append(source) }
        }
        switch slot {
        case .outerRing: result.append(.ring(.none))
        case .center: result.append(.center(.none))
        case .footer: result.append(.footer(.none))
        }
        return result
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
        let previousOuterRingPrimary = configuration.composition.outerRing.primary
        switch (slot, source) {
        case let (.outerRing, .ring(value)): configuration.composition.outerRing.primary = value
        case let (.center, .center(value)): configuration.composition.center.primary = value
        case let (.footer, .footer(value)): configuration.composition.footer.primary = value
        default: return false
        }
        configuration = configuration.normalized()
        if case .ring(.airPodsBattery) = source,
           previousOuterRingPrimary != .airPodsBattery,
           configuration.composition.outerRing.fallback == nil {
            configuration.composition.outerRing.fallback = .systemBattery
        }
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
    static func setBluetoothSymbolOverride(
        _ symbol: String?, for target: IconDesignerBehaviorTarget = .primary,
        in configuration: inout IconConfigurationV1,
        bluetoothTarget: IconDesignerBluetoothTarget = .currentAudioOutput,
        devices: [BluetoothDevice] = []
    ) -> Bool {
        let selected = source(for: target, slot: .center, in: configuration)
        let supportsSymbol: Bool
        switch selected {
        case .center(.bluetoothAudioOutput), .center(.pinnedBluetoothGlyph):
            supportsSymbol = true
        case .center(.connectedBluetoothDevice):
            supportsSymbol = IconDesignerBluetoothTargetModel.isAudioTarget(bluetoothTarget, devices: devices)
        default:
            supportsSymbol = false
        }
        guard supportsSymbol else {
            return false
        }
        configuration.behaviors.bluetoothAudioCenter.networkIconSymbolOverride = symbol
        configuration = configuration.normalized()
        return true
    }

    static func allowsNetworkProblemOverride(
        in configuration: IconConfigurationV1,
        bluetoothTarget: IconDesignerBluetoothTarget = .currentAudioOutput,
        devices: [BluetoothDevice] = []
    ) -> Bool {
        switch configuration.composition.center.primary {
        case .bluetoothAudioOutput:
            true
        case .connectedBluetoothDevice:
            IconDesignerBluetoothTargetModel.isAudioTarget(bluetoothTarget, devices: devices)
        default:
            false
        }
    }
}

extension IconDesignerSource {
    var pluginBinding: IconContentBinding? {
        switch self {
        case let .ring(source): IconContentLegacyAdapter.binding(for: source)
        case let .center(source): IconContentLegacyAdapter.binding(for: source)
        case let .footer(source): IconContentLegacyAdapter.binding(for: source)
        }
    }

    var localizationKey: LocalizationKey {
        guard let pluginBinding else { return .iconDesignerSourceNone }
        return BuiltinIconPlugins.makeRegistry().presentation(for: pluginBinding)?.title ?? .iconDesignerSourceNone
    }
}
