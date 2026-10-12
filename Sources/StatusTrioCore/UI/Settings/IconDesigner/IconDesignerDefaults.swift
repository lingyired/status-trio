import Foundation

enum IconDesignerDefaults {
    static func configuration() -> IconConfigurationV1 {
        var value = IconConfigurationV1.classic
        value.composition.outerRing = SlotSelection(primary: .systemBattery)
        value.composition.center = SlotSelection(primary: .network)
        value.composition.footer = SlotSelection(primary: .systemVolume)
        value.behaviors.airPodsRing = .dual
        value.appearance.center.normalizedSizePercentage = 1.0
        return value
    }

    static func resetting(_ slot: IconSlot, in configuration: IconConfigurationV1) -> IconConfigurationV1 {
        var value = configuration
        let defaults = Self.configuration()
        switch slot {
        case .outerRing:
            value.composition.outerRing = defaults.composition.outerRing
            value.behaviors.systemBatteryRing = defaults.behaviors.systemBatteryRing
            value.behaviors.airPodsRing = defaults.behaviors.airPodsRing
            value.appearance.outerRing = defaults.appearance.outerRing
        case .center:
            value.composition.center = defaults.composition.center
            value.composition.centerOverride = defaults.composition.centerOverride
            value.behaviors.networkCenter = defaults.behaviors.networkCenter
            value.behaviors.bluetoothAudioCenter = defaults.behaviors.bluetoothAudioCenter
            value.appearance.center = defaults.appearance.center
        case .footer:
            value.composition.footer = defaults.composition.footer
            value.behaviors.systemVolumeFooter = defaults.behaviors.systemVolumeFooter
            value.appearance.footer = defaults.appearance.footer
        }
        return value.normalized()
    }
}
