import Foundation

struct IconConfigurationV1: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var composition: IconCompositionConfiguration
    var behaviors: IconBehaviorConfiguration
    var appearance: IconAppearanceConfiguration
    /// Nil only in pre-consolidation V1 payloads that stored Wi-Fi scale twice.
    var wifiScaleMigrationVersion: Int? = 1
    /// Nil until the one-time centre-source compatibility migration has folded
    /// legacy input-source preferences into the explicit `.inputSource` source.
    var centerSourceMigrationVersion: Int? = 1

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
        let legacyWiFiScale = Self.bounded(
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
        copy.behaviors.hardwareRing = copy.behaviors.hardwareRing.normalized()

        if (copy.wifiScaleMigrationVersion ?? 0) < 1 {
            // Center appearance is shared by primary and fallback sources. Fold
            // Wi-Fi only when Network (or automaticLegacy) is primary, so an
            // unused Wi-Fi setting cannot enlarge a Bluetooth/battery primary.
            // A Network primary's fallback shares the migrated size; with an
            // explicit non-Wi-Fi primary, a Wi-Fi fallback loses its old
            // source-only multiplier because the shared Appearance size stays put.
            if copy.composition.center.primary == .network
                || copy.composition.center.primary == .automaticLegacy {
                copy.appearance.center.symbolScale = Self.bounded(
                    copy.appearance.center.symbolScale * legacyWiFiScale,
                    range: 1...3,
                    fallback: CenterAppearance.classic.symbolScale
                )
            }
            copy.wifiScaleMigrationVersion = 1
        }
        // Kept in the V1 shape for backward Codable compatibility; new configs
        // store all center sizing in appearance.center.symbolScale.
        copy.behaviors.networkCenter.wifiScale = NetworkCenterBehavior.classic.wifiScale
        return copy
    }

    func resetting(_ slot: IconSlot) -> Self {
        IconDesignerDefaults.resetting(slot, in: self)
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
