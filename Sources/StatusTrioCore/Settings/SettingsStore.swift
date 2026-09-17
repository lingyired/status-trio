import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    static let hasCompletedIconGuideOnboardingDefaultsKey = "hasCompletedIconGuideOnboarding.v1"
    static let hasSeenIconGuideDefaultsKey = "hasSeenIconGuide"
    private static let sparkleHasLaunchedBeforeDefaultsKey = "SUHasLaunchedBefore"

    static let iconSizeRange: ClosedRange<Double> = 16...36
    static let defaultIconSize: Double = 24
    static let iconSizeDefaultsKey = "menuBarIconSize"

    static let batteryCriticalThresholdRange: ClosedRange<Double> = 0...100
    static let defaultBatteryCriticalThreshold: Double = 20
    static let batterySymbolScaleRange: ClosedRange<Double> = 0.9...1.1
    static let defaultBatterySymbolScale: Double = 1
    static let showsBatteryPercentageDefaultsKey = "showsBatteryPercentage"
    static let showsChargingIndicatorDefaultsKey = "showsChargingIndicator"
    static let showsPercentageWhenConnectedDefaultsKey = "showsPercentageWhenConnected"
    static let usesBatteryStatusColorsDefaultsKey = "usesBatteryStatusColors"
    static let batteryCriticalThresholdDefaultsKey = "batteryCriticalThreshold"
    static let batterySymbolScaleDefaultsKey = "batterySymbolScale"
    static let showsWiFiIconForEthernetDefaultsKey = "showsWiFiIconForEthernet"
    static let showsWiFiIconForHotspotDefaultsKey = "showsWiFiIconForHotspot"
    static let showsWiFiIconForTemporaryConnectionDefaultsKey = "showsWiFiIconForTemporaryConnection"
    static let showsWiFiIconForInternetSharingDefaultsKey = "showsWiFiIconForInternetSharing"
    static let wifiSymbolScaleRange: ClosedRange<Double> = 1.0...1.8
    static let defaultWifiSymbolScale: Double = 1.6
    static let wifiSymbolScaleDefaultsKey = "wifiSymbolScale"
    static let defaultVolumeDisplayStyle: VolumeDisplayStyle = .dots
    static let volumeDisplayStyleDefaultsKey = "volumeDisplayStyle"

    static let refreshIntervalRange: ClosedRange<Double> = 5...60
    static let defaultRefreshIntervalSeconds: Double = 5
    static let refreshIntervalDefaultsKey = "statusRefreshIntervalSeconds"

    static let outputDeviceLimitRange: ClosedRange<Int> = 1...20
    static let defaultMaxVisibleOutputDevices = 5
    static let maxVisibleOutputDevicesDefaultsKey = "maxVisibleOutputDevices"
    static let alwaysShowsAllOutputDevicesDefaultsKey = "alwaysShowsAllOutputDevices"
    static let outputDeviceOrderDefaultsKey = "outputDeviceOrder"
    static let popupSectionOrderDefaultsKey = "popupSectionOrder"
    static let enabledPopupSectionsDefaultsKey = "enabledPopupSections"
    static let defaultEnabledPopupSections: Set<PopupSection> = [.battery, .network, .volume]
    static let popupScrollAdjustsVolumeDefaultsKey = "popupScrollAdjustsVolume"
    static let defaultPopupScrollAdjustsVolume = true
    static let popupVolumeScrollScopeDefaultsKey = "popupVolumeScrollScope"
    static let defaultPopupVolumeScrollScope: PopupVolumeScrollScope = .panel
    static let popupVolumeScrollDirectionDefaultsKey = "popupVolumeScrollDirection"
    static let defaultPopupVolumeScrollDirection: PopupVolumeScrollDirection = .up
    static let popupVolumeNaturalScrollingDefaultsKey = "popupVolumeNaturalScrolling"
    static let defaultPopupVolumeNaturalScrolling = false

    static let appIconPlacementDefaultsKey = "appIconPlacement"
    static let dockIconBackgroundPreferenceDefaultsKey = "dockIconBackgroundPreference"

    @Published var hasCompletedIconGuideOnboarding: Bool {
        didSet {
            defaults.set(
                hasCompletedIconGuideOnboarding,
                forKey: Self.hasCompletedIconGuideOnboardingDefaultsKey
            )
        }
    }

    @Published var appIconPlacement: AppIconPlacement {
        didSet {
            defaults.set(appIconPlacement.rawValue, forKey: Self.appIconPlacementDefaultsKey)
        }
    }

    @Published var dockIconBackgroundPreference: DockIconBackgroundPreference {
        didSet {
            defaults.set(
                dockIconBackgroundPreference.rawValue,
                forKey: Self.dockIconBackgroundPreferenceDefaultsKey
            )
        }
    }

    @Published var iconSize: Double {
        didSet {
            let clamped = Self.clampedIconSize(iconSize)
            // 写入越界值时先夹取再落盘，夹取会再次触发 didSet，一次后收敛。
            guard clamped == iconSize else {
                iconSize = clamped
                return
            }
            defaults.set(clamped, forKey: Self.iconSizeDefaultsKey)
        }
    }

    @Published var showsBatteryPercentage: Bool {
        didSet {
            defaults.set(showsBatteryPercentage, forKey: Self.showsBatteryPercentageDefaultsKey)
        }
    }

    @Published var showsChargingIndicator: Bool {
        didSet {
            defaults.set(showsChargingIndicator, forKey: Self.showsChargingIndicatorDefaultsKey)
        }
    }

    @Published var showsPercentageWhenConnected: Bool {
        didSet {
            defaults.set(
                showsPercentageWhenConnected,
                forKey: Self.showsPercentageWhenConnectedDefaultsKey
            )
        }
    }

    @Published var usesBatteryStatusColors: Bool {
        didSet {
            defaults.set(usesBatteryStatusColors, forKey: Self.usesBatteryStatusColorsDefaultsKey)
        }
    }

    @Published var batterySymbolScale: Double {
        didSet {
            let clamped = Self.clampedBatterySymbolScale(batterySymbolScale)
            guard clamped == batterySymbolScale else {
                batterySymbolScale = clamped
                return
            }
            defaults.set(clamped, forKey: Self.batterySymbolScaleDefaultsKey)
        }
    }

    @Published var batteryCriticalThreshold: Double {
        didSet {
            let clamped = Self.clampedBatteryCriticalThreshold(batteryCriticalThreshold)
            guard clamped == batteryCriticalThreshold else {
                batteryCriticalThreshold = clamped
                return
            }
            defaults.set(clamped, forKey: Self.batteryCriticalThresholdDefaultsKey)
        }
    }

    @Published var showsWiFiIconForEthernet: Bool {
        didSet {
            defaults.set(
                showsWiFiIconForEthernet,
                forKey: Self.showsWiFiIconForEthernetDefaultsKey
            )
        }
    }

    @Published var showsWiFiIconForHotspot: Bool {
        didSet {
            defaults.set(
                showsWiFiIconForHotspot,
                forKey: Self.showsWiFiIconForHotspotDefaultsKey
            )
        }
    }

    @Published var showsWiFiIconForTemporaryConnection: Bool {
        didSet {
            defaults.set(
                showsWiFiIconForTemporaryConnection,
                forKey: Self.showsWiFiIconForTemporaryConnectionDefaultsKey
            )
        }
    }

    @Published var showsWiFiIconForInternetSharing: Bool {
        didSet {
            defaults.set(
                showsWiFiIconForInternetSharing,
                forKey: Self.showsWiFiIconForInternetSharingDefaultsKey
            )
        }
    }

    @Published var wifiSymbolScale: Double {
        didSet {
            let clamped = Self.clampedWifiSymbolScale(wifiSymbolScale)
            guard clamped == wifiSymbolScale else {
                wifiSymbolScale = clamped
                return
            }
            defaults.set(clamped, forKey: Self.wifiSymbolScaleDefaultsKey)
        }
    }

    @Published var volumeDisplayStyle: VolumeDisplayStyle {
        didSet {
            defaults.set(volumeDisplayStyle.rawValue, forKey: Self.volumeDisplayStyleDefaultsKey)
        }
    }

    @Published var refreshIntervalSeconds: Double {
        didSet {
            let clamped = Self.clampedRefreshInterval(refreshIntervalSeconds)
            guard clamped == refreshIntervalSeconds else {
                refreshIntervalSeconds = clamped
                return
            }
            defaults.set(clamped, forKey: Self.refreshIntervalDefaultsKey)
        }
    }

    @Published var maxVisibleOutputDevices: Int {
        didSet {
            let clamped = Self.clampedOutputDeviceLimit(maxVisibleOutputDevices)
            guard clamped == maxVisibleOutputDevices else {
                maxVisibleOutputDevices = clamped
                return
            }
            defaults.set(clamped, forKey: Self.maxVisibleOutputDevicesDefaultsKey)
        }
    }

    @Published var alwaysShowsAllOutputDevices: Bool {
        didSet {
            defaults.set(
                alwaysShowsAllOutputDevices,
                forKey: Self.alwaysShowsAllOutputDevicesDefaultsKey
            )
        }
    }

    @Published private(set) var outputDeviceOrder: [String] {
        didSet {
            defaults.set(outputDeviceOrder, forKey: Self.outputDeviceOrderDefaultsKey)
        }
    }

    @Published private(set) var popupSectionOrder: [PopupSection] {
        didSet {
            defaults.set(
                popupSectionOrder.map(\.rawValue),
                forKey: Self.popupSectionOrderDefaultsKey
            )
        }
    }

    @Published private(set) var enabledPopupSections: Set<PopupSection> {
        didSet {
            defaults.set(
                enabledPopupSections.map(\.rawValue).sorted(),
                forKey: Self.enabledPopupSectionsDefaultsKey
            )
        }
    }

    @Published var popupScrollAdjustsVolume: Bool {
        didSet {
            defaults.set(
                popupScrollAdjustsVolume,
                forKey: Self.popupScrollAdjustsVolumeDefaultsKey
            )
        }
    }

    @Published var popupVolumeScrollScope: PopupVolumeScrollScope {
        didSet {
            defaults.set(
                popupVolumeScrollScope.rawValue,
                forKey: Self.popupVolumeScrollScopeDefaultsKey
            )
        }
    }

    @Published var popupVolumeScrollDirection: PopupVolumeScrollDirection {
        didSet {
            defaults.set(
                popupVolumeScrollDirection.rawValue,
                forKey: Self.popupVolumeScrollDirectionDefaultsKey
            )
        }
    }

    @Published var popupVolumeNaturalScrolling: Bool {
        didSet {
            defaults.set(
                popupVolumeNaturalScrolling,
                forKey: Self.popupVolumeNaturalScrollingDefaultsKey
            )
        }
    }

    var visiblePopupSections: [PopupSection] {
        popupSectionOrder.filter { enabledPopupSections.contains($0) }
    }

    var refreshInterval: Duration {
        .seconds(Int(refreshIntervalSeconds.rounded()))
    }

    var visibleOutputDeviceLimit: Int? {
        alwaysShowsAllOutputDevices ? nil : maxVisibleOutputDevices
    }

    func orderedOutputDevices(_ devices: [AudioOutputDevice]) -> [AudioOutputDevice] {
        OutputDeviceListPresentation.orderedDevices(devices, using: outputDeviceOrder)
    }

    func moveOutputDevices(
        fromOffsets source: IndexSet,
        toOffset destination: Int,
        in devices: [AudioOutputDevice]
    ) {
        guard !source.isEmpty,
              source.allSatisfy({ devices.indices.contains($0) }),
              (0...devices.count).contains(destination) else {
            return
        }

        let movedDevices = source.map { devices[$0] }
        let remainingDevices = devices.enumerated()
            .filter { !source.contains($0.offset) }
            .map(\.element)
        let insertionOffset = destination - source.filter { $0 < destination }.count

        var reorderedDevices = remainingDevices
        reorderedDevices.insert(
            contentsOf: movedDevices,
            at: min(insertionOffset, reorderedDevices.count)
        )
        outputDeviceOrder = reorderedDevices.compactMap(\.uid)
    }

    func movePopupSections(
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) {
        guard !source.isEmpty,
              source.allSatisfy({ popupSectionOrder.indices.contains($0) }),
              (0...popupSectionOrder.count).contains(destination) else {
            return
        }

        let movedSections = source.map { popupSectionOrder[$0] }
        let remainingSections = popupSectionOrder.enumerated()
            .filter { !source.contains($0.offset) }
            .map(\.element)
        let insertionOffset = destination - source.filter { $0 < destination }.count

        var reorderedSections = remainingSections
        reorderedSections.insert(
            contentsOf: movedSections,
            at: min(insertionOffset, reorderedSections.count)
        )
        popupSectionOrder = reorderedSections
    }

    func setPopupSection(_ section: PopupSection, enabled: Bool) {
        if enabled {
            enabledPopupSections.insert(section)
        } else {
            enabledPopupSections.remove(section)
        }
    }

    var isBatterySymbolSizeEnabled: Bool {
        showsBatteryPercentage || showsChargingIndicator
    }

    var batteryIconOptions: BatteryIconOptions {
        BatteryIconOptions(
            showsPercentage: showsBatteryPercentage,
            showsChargingIndicator: showsChargingIndicator,
            usesStatusColors: usesBatteryStatusColors,
            criticalThreshold: Int(batteryCriticalThreshold.rounded()),
            showsPercentageWhenConnected: showsPercentageWhenConnected,
            textScale: batterySymbolScale * BatteryIconOptions.defaultTextScale
        )
    }

    var connectionIconOptions: ConnectionIconOptions {
        ConnectionIconOptions(
            showsWiFiIconForEthernet: showsWiFiIconForEthernet,
            showsWiFiIconForHotspot: showsWiFiIconForHotspot,
            showsWiFiIconForTemporaryConnection: showsWiFiIconForTemporaryConnection,
            showsWiFiIconForInternetSharing: showsWiFiIconForInternetSharing,
            wifiScale: wifiSymbolScale
        )
    }

    var volumeIconOptions: VolumeIconOptions {
        VolumeIconOptions(displayStyle: volumeDisplayStyle)
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Self.hasCompletedIconGuideOnboardingDefaultsKey) != nil {
            self.hasCompletedIconGuideOnboarding = defaults.bool(
                forKey: Self.hasCompletedIconGuideOnboardingDefaultsKey
            )
        } else {
            // Sparkle writes this before its first update check. AppDelegate requests
            // onboarding before starting Sparkle, so its presence identifies upgrades.
            let isExistingInstallation =
                defaults.bool(forKey: Self.sparkleHasLaunchedBeforeDefaultsKey)
                || defaults.bool(forKey: Self.hasSeenIconGuideDefaultsKey)
            self.hasCompletedIconGuideOnboarding = isExistingInstallation
            defaults.set(
                isExistingInstallation,
                forKey: Self.hasCompletedIconGuideOnboardingDefaultsKey
            )
        }
        let storedIconSize = (defaults.object(forKey: Self.iconSizeDefaultsKey) as? NSNumber)?.doubleValue
        let storedCriticalThreshold = (defaults.object(forKey: Self.batteryCriticalThresholdDefaultsKey) as? NSNumber)?.doubleValue
        let storedBatterySymbolScale = (defaults.object(forKey: Self.batterySymbolScaleDefaultsKey) as? NSNumber)?.doubleValue
        let storedOutputDeviceLimit = (defaults.object(forKey: Self.maxVisibleOutputDevicesDefaultsKey) as? NSNumber)?.intValue
        let storedRefreshInterval = (defaults.object(forKey: Self.refreshIntervalDefaultsKey) as? NSNumber)?.doubleValue
        let storedWifiSymbolScale = (defaults.object(forKey: Self.wifiSymbolScaleDefaultsKey) as? NSNumber)?.doubleValue
        let storedVolumeDisplayStyle = defaults.string(forKey: Self.volumeDisplayStyleDefaultsKey)
        let storedOutputDeviceOrder = defaults.stringArray(forKey: Self.outputDeviceOrderDefaultsKey) ?? []
        let storedPopupSectionOrder = defaults.stringArray(
            forKey: Self.popupSectionOrderDefaultsKey
        ) ?? []
        let storedEnabledPopupSections = defaults.stringArray(
            forKey: Self.enabledPopupSectionsDefaultsKey
        )
        let storedPopupVolumeScrollScope = defaults.string(
            forKey: Self.popupVolumeScrollScopeDefaultsKey
        )
        let storedPopupVolumeScrollDirection = defaults.string(
            forKey: Self.popupVolumeScrollDirectionDefaultsKey
        )

        let storedAppIconPlacement = defaults.string(forKey: Self.appIconPlacementDefaultsKey)
        self.appIconPlacement = storedAppIconPlacement
            .flatMap(AppIconPlacement.init(rawValue:))
            ?? .menuBar
        let storedDockIconBackgroundPreference = defaults.string(
            forKey: Self.dockIconBackgroundPreferenceDefaultsKey
        )
        self.dockIconBackgroundPreference = storedDockIconBackgroundPreference
            .flatMap(DockIconBackgroundPreference.init(rawValue:))
            ?? .system
        self.iconSize = Self.clampedIconSize(storedIconSize ?? Self.defaultIconSize)
        self.showsBatteryPercentage = defaults.object(forKey: Self.showsBatteryPercentageDefaultsKey) as? Bool ?? true
        self.showsChargingIndicator = defaults.object(forKey: Self.showsChargingIndicatorDefaultsKey) as? Bool ?? true
        self.showsPercentageWhenConnected = defaults.object(
            forKey: Self.showsPercentageWhenConnectedDefaultsKey
        ) as? Bool ?? false
        self.usesBatteryStatusColors = defaults.object(forKey: Self.usesBatteryStatusColorsDefaultsKey) as? Bool ?? true
        self.batterySymbolScale = Self.clampedBatterySymbolScale(
            storedBatterySymbolScale ?? Self.defaultBatterySymbolScale
        )
        self.batteryCriticalThreshold = Self.clampedBatteryCriticalThreshold(
            storedCriticalThreshold ?? Self.defaultBatteryCriticalThreshold
        )
        self.showsWiFiIconForEthernet = defaults.object(
            forKey: Self.showsWiFiIconForEthernetDefaultsKey
        ) as? Bool ?? false
        self.showsWiFiIconForHotspot = defaults.object(
            forKey: Self.showsWiFiIconForHotspotDefaultsKey
        ) as? Bool ?? false
        self.showsWiFiIconForTemporaryConnection = defaults.object(
            forKey: Self.showsWiFiIconForTemporaryConnectionDefaultsKey
        ) as? Bool ?? false
        self.showsWiFiIconForInternetSharing = defaults.object(
            forKey: Self.showsWiFiIconForInternetSharingDefaultsKey
        ) as? Bool ?? false
        self.wifiSymbolScale = Self.clampedWifiSymbolScale(
            storedWifiSymbolScale ?? Self.defaultWifiSymbolScale
        )
        self.volumeDisplayStyle = storedVolumeDisplayStyle
            .flatMap(VolumeDisplayStyle.init(rawValue:))
            ?? Self.defaultVolumeDisplayStyle
        self.refreshIntervalSeconds = Self.clampedRefreshInterval(
            storedRefreshInterval ?? Self.defaultRefreshIntervalSeconds
        )
        self.maxVisibleOutputDevices = Self.clampedOutputDeviceLimit(
            storedOutputDeviceLimit ?? Self.defaultMaxVisibleOutputDevices
        )
        self.alwaysShowsAllOutputDevices = defaults.object(
            forKey: Self.alwaysShowsAllOutputDevicesDefaultsKey
        ) as? Bool ?? false
        self.outputDeviceOrder = storedOutputDeviceOrder
        self.popupSectionOrder = Self.sanitizedPopupSectionOrder(
            storedPopupSectionOrder
        )
        self.enabledPopupSections = Self.sanitizedEnabledPopupSections(
            storedEnabledPopupSections
        )
        self.popupScrollAdjustsVolume = defaults.object(
            forKey: Self.popupScrollAdjustsVolumeDefaultsKey
        ) as? Bool ?? Self.defaultPopupScrollAdjustsVolume
        self.popupVolumeScrollScope = storedPopupVolumeScrollScope
            .flatMap(PopupVolumeScrollScope.init(rawValue:))
            ?? Self.defaultPopupVolumeScrollScope
        self.popupVolumeScrollDirection = storedPopupVolumeScrollDirection
            .flatMap(PopupVolumeScrollDirection.init(rawValue:))
            ?? Self.defaultPopupVolumeScrollDirection
        self.popupVolumeNaturalScrolling = defaults.object(
            forKey: Self.popupVolumeNaturalScrollingDefaultsKey
        ) as? Bool ?? Self.defaultPopupVolumeNaturalScrolling
    }

    static func clampedIconSize(_ value: Double) -> Double {
        guard value.isFinite else { return defaultIconSize }
        return min(iconSizeRange.upperBound, max(iconSizeRange.lowerBound, value))
    }

    static func clampedBatterySymbolScale(_ value: Double) -> Double {
        guard value.isFinite else { return defaultBatterySymbolScale }
        return min(
            batterySymbolScaleRange.upperBound,
            max(batterySymbolScaleRange.lowerBound, value)
        )
    }

    static func clampedWifiSymbolScale(_ value: Double) -> Double {
        guard value.isFinite else { return defaultWifiSymbolScale }
        return min(
            wifiSymbolScaleRange.upperBound,
            max(wifiSymbolScaleRange.lowerBound, value)
        )
    }

    static func clampedBatteryCriticalThreshold(_ value: Double) -> Double {
        guard value.isFinite else { return defaultBatteryCriticalThreshold }
        return min(
            batteryCriticalThresholdRange.upperBound,
            max(batteryCriticalThresholdRange.lowerBound, value)
        ).rounded()
    }

    static func clampedRefreshInterval(_ value: Double) -> Double {
        guard value.isFinite else { return defaultRefreshIntervalSeconds }
        let clamped = min(refreshIntervalRange.upperBound, max(refreshIntervalRange.lowerBound, value))
        return (clamped / 5).rounded() * 5
    }

    static func clampedOutputDeviceLimit(_ value: Int) -> Int {
        min(outputDeviceLimitRange.upperBound, max(outputDeviceLimitRange.lowerBound, value))
    }

    static func sanitizedPopupSectionOrder(_ rawValues: [String]) -> [PopupSection] {
        var seen: Set<PopupSection> = []
        let storedSections = rawValues
            .compactMap(PopupSection.init(rawValue:))
            .filter { seen.insert($0).inserted }
        return storedSections + PopupSection.allCases.filter { !seen.contains($0) }
    }

    static func sanitizedEnabledPopupSections(_ rawValues: [String]?) -> Set<PopupSection> {
        guard let rawValues else {
            return defaultEnabledPopupSections
        }
        return Set(rawValues.compactMap(PopupSection.init(rawValue:)))
    }
}
