import Combine
import Foundation

@MainActor
final class IconDesignerPreviewSession: ObservableObject {
    @Published var mode: IconPreviewDataMode = .live {
        didSet {
            if mode != .simulated, appliesToRealIcons {
                appliesToRealIcons = false
            }
            realIconOverrideChanges.send()
        }
    }
    /// Opt-in only for a temporary, in-memory test of the real Menu Bar and
    /// Dock icons. This must never be written to settings or restored on launch.
    @Published private(set) var appliesToRealIcons = false
    @Published var selectedSlot: IconSlot = .outerRing
    @Published var expandedFallbackSlots: Set<IconSlot> = []
    /// Shared preview-only appearance; it is intentionally outside settings and edit history.
    @Published var isDarkBackground = true
    @Published private(set) var samples = IconPreviewSampleValues() {
        didSet { realIconOverrideChanges.send() }
    }
    /// Emits after the values above have been stored, unlike `@Published`.
    let realIconOverrideChanges = PassthroughSubject<Void, Never>()

    var canApplyToRealIcons: Bool {
        mode == .simulated
    }

    func setAppliesToRealIcons(_ enabled: Bool) {
        let next = enabled && canApplyToRealIcons
        guard appliesToRealIcons != next else { return }
        appliesToRealIcons = next
        realIconOverrideChanges.send()
    }

    func updateSamples(_ update: (inout IconPreviewSampleValues) -> Void) {
        var updated = samples
        update(&updated)
        updated.macBattery.percentage = min(100, max(0, updated.macBattery.percentage))
        updated.airPods.setLeftBattery(Double(updated.airPods.leftBattery))
        updated.airPods.setRightBattery(Double(updated.airPods.rightBattery))
        updated.network.rssi = updated.network.clampedRSSI
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

    func setNetworkRSSI(_ value: Double) {
        updateSamples {
            let range = NetworkPreviewSample.rssiRange
            let finiteValue = value.isFinite ? value : -48
            $0.network.rssi = Int(min(Double(range.upperBound), max(Double(range.lowerBound), finiteValue.rounded())))
        }
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
        IconContentDependencyResolver.dependencies(configuration: configuration,
            targetIsAudio: Self.isAudioTarget(target, devices: devices)).samples
    }

    static func isAudioTarget(_ target: IconDesignerBluetoothTarget, devices: [BluetoothDevice]) -> Bool {
        IconDesignerBluetoothTargetModel.isAudioTarget(target, devices: devices)
    }

    private static func safePercentage(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(100, max(0, value.rounded())))
    }
}
