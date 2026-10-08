import Foundation

struct IconConfigurationV1: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var composition: IconCompositionConfiguration
    var behaviors: IconBehaviorConfiguration
    var appearance: IconAppearanceConfiguration

    static let classic = Self(
        schemaVersion: 1,
        composition: .classic,
        behaviors: .classic,
        appearance: .classic
    )

    func normalized() -> Self {
        var copy = self
        copy.composition.outerRing = Self.normalized(copy.composition.outerRing, none: .none)
        copy.composition.center = Self.normalized(copy.composition.center, none: .none)
        copy.composition.footer = Self.normalized(copy.composition.footer, none: .none)
        copy.behaviors.systemBatteryRing.criticalThreshold = min(100, max(0, copy.behaviors.systemBatteryRing.criticalThreshold))
        copy.behaviors.systemBatteryRing.textScale = Self.bounded(
            copy.behaviors.systemBatteryRing.textScale,
            range: 1...3,
            fallback: SystemBatteryRingBehavior.classic.textScale
        )
        copy.behaviors.networkCenter.wifiScale = Self.bounded(
            copy.behaviors.networkCenter.wifiScale,
            range: 0.5...3,
            fallback: NetworkCenterBehavior.classic.wifiScale
        )
        copy.behaviors.bluetoothAudioCenter.symbolScale = Self.bounded(
            copy.behaviors.bluetoothAudioCenter.symbolScale,
            range: 1...3,
            fallback: BluetoothAudioCenterBehavior.classic.symbolScale
        )
        copy.appearance.outerRing = copy.appearance.outerRing.normalized()
        copy.appearance.center = copy.appearance.center.normalized()
        copy.appearance.footer = copy.appearance.footer.normalized()
        return copy
    }

    func resetting(_ slot: IconSlot) -> Self {
        var copy = self
        let classic = Self.classic
        switch slot {
        case .outerRing:
            copy.composition.outerRing = classic.composition.outerRing
            copy.behaviors.systemBatteryRing = classic.behaviors.systemBatteryRing
            copy.appearance.outerRing = classic.appearance.outerRing
        case .center:
            copy.composition.center = classic.composition.center
            copy.composition.centerOverride = classic.composition.centerOverride
            copy.behaviors.networkCenter = classic.behaviors.networkCenter
            copy.behaviors.bluetoothAudioCenter = classic.behaviors.bluetoothAudioCenter
            copy.appearance.center = classic.appearance.center
        case .footer:
            copy.composition.footer = classic.composition.footer
            copy.behaviors.systemVolumeFooter = classic.behaviors.systemVolumeFooter
            copy.appearance.footer = classic.appearance.footer
        }
        return copy.normalized()
    }

    private static func normalized<Source: Codable & Hashable & Sendable>(
        _ selection: SlotSelection<Source>, none: Source
    ) -> SlotSelection<Source> {
        guard selection.primary != none else {
            return SlotSelection(primary: none)
        }
        guard let fallback = selection.fallback, fallback != none, fallback != selection.primary else {
            return SlotSelection(primary: selection.primary)
        }
        return selection
    }

    private static func bounded(_ value: Double, range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}
