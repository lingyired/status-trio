import Combine
import Foundation

@MainActor
final class IconDesignerPreviewSession: ObservableObject {
    @Published var mode: IconPreviewDataMode = .live
    @Published var selectedSlot: IconSlot = .outerRing
    /// Shared preview-only appearance; it is intentionally outside settings and edit history.
    @Published var isDarkBackground = true
    @Published private(set) var samples = IconPreviewSampleValues()

    func updateSamples(_ update: (inout IconPreviewSampleValues) -> Void) {
        var updated = samples
        update(&updated)
        updated.macBattery.percentage = min(100, max(0, updated.macBattery.percentage))
        updated.airPods.setLeftBattery(Double(updated.airPods.leftBattery))
        updated.airPods.setRightBattery(Double(updated.airPods.rightBattery))
        updated.systemVolume.percentage = min(100, max(0, updated.systemVolume.percentage))
        samples = updated
    }

    func setMacBatteryPercentage(_ value: Double) {
        var updated = samples
        updated.macBattery.percentage = Self.safePercentage(value)
        samples = updated
    }

    func setAirPodsAvailability(_ ear: IconPreviewEar, isAvailable: Bool) {
        var updated = samples
        switch ear {
        case .left:
            updated.airPods.leftAvailable = isAvailable
        case .right:
            updated.airPods.rightAvailable = isAvailable
        }
        samples = updated
    }

    func setAirPodsBattery(_ ear: IconPreviewEar, _ value: Double) {
        var updated = samples
        switch ear {
        case .left:
            updated.airPods.setLeftBattery(value)
        case .right:
            updated.airPods.setRightBattery(value)
        }
        samples = updated
    }

    func setSystemVolumePercentage(_ value: Double) {
        var updated = samples
        updated.systemVolume.percentage = Self.safePercentage(value)
        samples = updated
    }

    func applyAirPodsPreset(_ preset: CustomAirPodsPreviewPreset) {
        var updated = samples
        updated.airPods.apply(preset)
        samples = updated
    }

    /// Fills sample values once. It deliberately does not change preview mode;
    /// the data panel's segmented control is the only user-facing mode selector.
    func applyQuickFill(_ fill: IconPreviewQuickFill) {
        let scenario = fill.scenario
        var updated = samples
        switch scenario {
        case .live:
            break
        case .networkHealthy:
            updated.network.kind = .wifi
        case .networkNoInternet:
            updated.network.kind = .noInternet
        case .wifiOffEthernetConnected:
            updated.network.kind = .ethernet
        case .batteryCharging:
            updated.macBattery.isPresent = true
            updated.macBattery.percentage = 72
            updated.macBattery.isCharging = true
        case .batteryCriticallyLow:
            updated.macBattery.isPresent = true
            updated.macBattery.percentage = 8
            updated.macBattery.isCharging = false
        case .volumeMuted:
            updated.systemVolume.percentage = 0
            updated.systemVolume.isMuted = true
        case .airPodsConnected:
            updated.airPods.apply(.both)
        case .airPodsDisconnected:
            updated.airPods.apply(.unavailable)
        case .airPodsCustom:
            break
        }

        samples = updated
    }

    static func usedSources(
        configuration: IconConfigurationV1,
        target: IconDesignerBluetoothTarget,
        devices: [BluetoothDevice]
    ) -> Set<IconPreviewSampleSource> {
        var used = Set<IconPreviewSampleSource>()

        for source in [configuration.composition.outerRing.primary, configuration.composition.outerRing.fallback].compactMap({ $0 }) {
            switch source {
            case .systemBattery: used.insert(.macBattery)
            case .airPodsBattery: used.insert(.airPods)
            case .automaticLegacy, .none: break
            }
        }

        let centerSources = [configuration.composition.center.primary, configuration.composition.center.fallback].compactMap { $0 }
        for source in centerSources {
            switch source {
            case .inputSource:
                used.insert(.inputSource)
            case .network:
                used.insert(.network)
            case .systemBatteryPercentage:
                used.insert(.macBattery)
            case .bluetoothAudioOutput, .pinnedBluetoothGlyph, .connectedBluetoothDevice:
                used.insert(.bluetoothTarget)
            case .automaticLegacy, .none:
                break
            }
        }

        // The global network-failure rule can replace ANY centre source
        // (input method, battery, Bluetooth, network, legacy and none) with the
        // network scene, so the simulated-data editor always keeps the network
        // sample reachable while it is on.
        if configuration.composition.centerOverride.networkProblemOverridesPrimary {
            used.insert(.network)
        }

        for source in [configuration.composition.footer.primary, configuration.composition.footer.fallback].compactMap({ $0 }) {
            if source == .systemVolume { used.insert(.systemVolume) }
        }

        let centerUsesBluetooth = centerSources.contains {
            $0 == .bluetoothAudioOutput || $0 == .pinnedBluetoothGlyph || $0 == .connectedBluetoothDevice
        }
        if centerUsesBluetooth, configuration.behaviors.bluetoothAudioCenter.usesVolumeColor,
           Self.isAudioTarget(target, devices: devices) {
            used.insert(.systemVolume)
        }

        return used
    }

    static func isAudioTarget(_ target: IconDesignerBluetoothTarget, devices: [BluetoothDevice]) -> Bool {
        IconDesignerBluetoothTargetModel.isAudioTarget(target, devices: devices)
    }

    private static func safePercentage(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(100, max(0, value.rounded())))
    }
}
