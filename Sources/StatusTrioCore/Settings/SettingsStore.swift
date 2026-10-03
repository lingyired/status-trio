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
    static let showsChargingEffectDefaultsKey = "showsChargingEffect"
    static let showsChargingBoltHeartbeatDefaultsKey = "showsChargingBoltHeartbeat"
    static let showsPercentageWhenConnectedDefaultsKey = "showsPercentageWhenConnected"
    static let usesBatteryStatusColorsDefaultsKey = "usesBatteryStatusColors"
    static let batteryCriticalThresholdDefaultsKey = "batteryCriticalThreshold"
    static let batterySymbolScaleDefaultsKey = "batterySymbolScale"
    static let showsWiFiIconForEthernetDefaultsKey = "showsWiFiIconForEthernet"
    static let showsWiFiIconForHotspotDefaultsKey = "showsWiFiIconForHotspot"
    static let showsWiFiIconForTemporaryConnectionDefaultsKey = "showsWiFiIconForTemporaryConnection"
    static let showsWiFiIconForInternetSharingDefaultsKey = "showsWiFiIconForInternetSharing"
    static let showsBatteryPercentageInConnectionSlotDefaultsKey = "showsBatteryPercentageInConnectionSlot"
    static let replacesNetworkIconWithBluetoothAudioDefaultsKey = "replacesNetworkIconWithBluetoothAudio"
    static let usesBluetoothAudioVolumeColorDefaultsKey = "usesBluetoothAudioVolumeColor"
    static let prioritizesNetworkErrorsOverBluetoothAudioDefaultsKey = "prioritizesNetworkErrorsOverBluetoothAudio"
    static let showsBluetoothBatteryLevelsDefaultsKey = "showsBluetoothBatteryLevels"
    static let showsNearbyBluetoothBatteryDevicesDefaultsKey = "showsNearbyBluetoothBatteryDevices"
    static let showsMobileDeviceBatteryLevelsDefaultsKey = "showsMobileDeviceBatteryLevels"
    static let previewsBluetoothListeningModeDefaultsKey = "previewsBluetoothListeningMode"
    static let bluetoothListeningModePreviewDeviceNameDefaultsKey = "bluetoothListeningModePreviewDeviceName"
    static let bluetoothListeningModePreviewDeviceCountDefaultsKey = "bluetoothListeningModePreviewDeviceCount"
    static let bluetoothListeningModePreviewLanguageDefaultsKey = "bluetoothListeningModePreviewLanguage"
    static let bluetoothListeningModePreviewDeviceCountRange: ClosedRange<Int> = 0...3
    static let defaultBluetoothListeningModePreviewDeviceCount = 2
    static let statusCenterSymbolScaleRange: ClosedRange<Double> = 1.0...1.8
    static let defaultStatusCenterSymbolScale: Double = 1.6
    static let bluetoothSymbolScaleRange = statusCenterSymbolScaleRange
    static let defaultBluetoothSymbolScale = defaultStatusCenterSymbolScale
    static let bluetoothSymbolScaleDefaultsKey = "bluetoothSymbolScale"
    static let wifiSymbolScaleRange = statusCenterSymbolScaleRange
    static let defaultWifiSymbolScale = defaultStatusCenterSymbolScale
    static let wifiSymbolScaleDefaultsKey = "wifiSymbolScale"
    static let defaultVolumeDisplayStyle: VolumeDisplayStyle = .dots
    static let volumeDisplayStyleDefaultsKey = "volumeDisplayStyle"
    static let defaultRingStrokeStyle: RingStrokeStyle = .regular
    static let ringStrokeStyleDefaultsKey = "ringStrokeStyle"

    static let refreshIntervalRange: ClosedRange<Double> = 5...60
    /// The fallback poll sits behind push channels, so its steady-state cadence
    /// is a watchdog rather than the primary update path. 15 seconds keeps the
    /// icon honest without waking the CPU every 5; 5 stays available in
    /// `refreshIntervalRange` for anyone who wants the old cadence.
    static let defaultRefreshIntervalSeconds: Double = 15
    static let refreshIntervalDefaultsKey = "statusRefreshIntervalSeconds"

    static let outputDeviceLimitRange: ClosedRange<Int> = 1...20
    static let defaultMaxVisibleOutputDevices = 5
    static let maxVisibleOutputDevicesDefaultsKey = "maxVisibleOutputDevices"
    static let defaultMaxVisibleBluetoothDevices = 5
    static let maxVisibleBluetoothDevicesDefaultsKey = "maxVisibleBluetoothDevices"
    static let showsBluetoothDeviceListDefaultsKey = "showsBluetoothDeviceList"
    static let bluetoothDeviceOrderDefaultsKey = "bluetoothDeviceOrder"
    static let hidesGhostBluetoothDevicesDefaultsKey = "hidesGhostBluetoothDevices"
    static let hiddenBluetoothDeviceAddressesDefaultsKey = "hiddenBluetoothDeviceAddresses"
    static let revealedGhostBluetoothDeviceAddressesDefaultsKey = "revealedGhostBluetoothDeviceAddresses"
    static let bluetoothNetworkIconDeviceAddressDefaultsKey = "bluetoothNetworkIconDeviceAddress"
    static let bluetoothNetworkIconSymbolNameDefaultsKey = "bluetoothNetworkIconSymbolName"
    static let bluetoothDeviceLimitRange: ClosedRange<Int> = 1...20
    static let alwaysShowsAllOutputDevicesDefaultsKey = "alwaysShowsAllOutputDevices"
    static let outputDeviceOrderDefaultsKey = "outputDeviceOrder"
    static let popupSectionOrderDefaultsKey = "popupSectionOrder"
    static let enabledPopupSectionsDefaultsKey = "enabledPopupSections"
    static let defaultEnabledPopupSections: Set<PopupSection> = [.battery, .network, .vpn, .volume]
    /// Set once the VPN row has been offered to a stored section list.
    ///
    /// `defaultEnabledPopupSections` only reaches a user who has never saved
    /// the list, so the row is added to an existing list exactly once instead —
    /// after that, a stored list without `.vpn` means the user switched the row
    /// off, and that choice has to survive every later launch.
    static let vpnPopupSectionIntroducedDefaultsKey = "vpnPopupSectionIntroduced.v1"
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

    @Published var showsChargingEffect: Bool {
        didSet {
            defaults.set(showsChargingEffect, forKey: Self.showsChargingEffectDefaultsKey)
            if !showsChargingEffect {
                testsChargingEffect = false
            }
        }
    }

    @Published var showsChargingBoltHeartbeat: Bool {
        didSet {
            defaults.set(
                showsChargingBoltHeartbeat,
                forKey: Self.showsChargingBoltHeartbeatDefaultsKey
            )
        }
    }

    @Published private(set) var testsChargingEffect = false

    func setChargingEffectTestEnabled(_ enabled: Bool) {
        if enabled {
            showsChargingEffect = true
        }
        testsChargingEffect = enabled
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

    @Published var showsBatteryPercentageInConnectionSlot: Bool {
        didSet {
            defaults.set(
                showsBatteryPercentageInConnectionSlot,
                forKey: Self.showsBatteryPercentageInConnectionSlotDefaultsKey
            )
        }
    }

    @Published var replacesNetworkIconWithBluetoothAudio: Bool {
        didSet {
            defaults.set(
                replacesNetworkIconWithBluetoothAudio,
                forKey: Self.replacesNetworkIconWithBluetoothAudioDefaultsKey
            )
        }
    }

    @Published var usesBluetoothAudioVolumeColor: Bool {
        didSet {
            defaults.set(
                usesBluetoothAudioVolumeColor,
                forKey: Self.usesBluetoothAudioVolumeColorDefaultsKey
            )
        }
    }

    @Published var prioritizesNetworkErrorsOverBluetoothAudio: Bool {
        didSet {
            defaults.set(
                prioritizesNetworkErrorsOverBluetoothAudio,
                forKey: Self.prioritizesNetworkErrorsOverBluetoothAudioDefaultsKey
            )
        }
    }

    @Published var showsBluetoothBatteryLevels: Bool {
        didSet {
            defaults.set(
                showsBluetoothBatteryLevels,
                forKey: Self.showsBluetoothBatteryLevelsDefaultsKey
            )
        }
    }

    @Published var showsNearbyBluetoothBatteryDevices: Bool {
        didSet {
            defaults.set(
                showsNearbyBluetoothBatteryDevices,
                forKey: Self.showsNearbyBluetoothBatteryDevicesDefaultsKey
            )
        }
    }

    @Published var showsMobileDeviceBatteryLevels: Bool {
        didSet {
            defaults.set(
                showsMobileDeviceBatteryLevels,
                forKey: Self.showsMobileDeviceBatteryLevelsDefaultsKey
            )
        }
    }

    /// Interface preview for the AirPods listening-mode switch. When on, every
    /// connected AirPods row shows the three mode capsules and tapping them
    /// drives the same busy → settled animation, but no CoreAudio write is
    /// issued. The toggle exists so the row's layout, focus order, and tap
    /// feedback can be exercised on a Mac that has no controllable AirPods
    /// attached; it is off by default so a normal user never sees a
    /// non-functional capsule.
    @Published var previewsBluetoothListeningMode: Bool {
        didSet {
            defaults.set(
                previewsBluetoothListeningMode,
                forKey: Self.previewsBluetoothListeningModeDefaultsKey
            )
        }
    }

    /// Optional override for the synthetic preview rows' device name. Empty means
    /// "use the built-in default", which already contains the string "AirPods"
    /// — an override without that substring still works because the synthetic
    /// addresses are prefixed, and the preview controller admits any
    /// preview-prefixed device regardless of `isAirPods`.
    @Published var bluetoothListeningModePreviewDeviceName: String {
        didSet {
            defaults.set(
                bluetoothListeningModePreviewDeviceName,
                forKey: Self.bluetoothListeningModePreviewDeviceNameDefaultsKey
            )
        }
    }

    /// How many synthetic AirPods rows to inject in preview. 0...3. Default 2,
    /// which is enough to check both the wrapped layout on one row and the list's
    /// 330pt scroll boundary on two.
    @Published var bluetoothListeningModePreviewDeviceCount: Int {
        didSet {
            let range = Self.bluetoothListeningModePreviewDeviceCountRange
            let clamped = min(max(bluetoothListeningModePreviewDeviceCount, range.lowerBound), range.upperBound)
            guard clamped == bluetoothListeningModePreviewDeviceCount else {
                bluetoothListeningModePreviewDeviceCount = clamped
                return
            }
            defaults.set(
                clamped,
                forKey: Self.bluetoothListeningModePreviewDeviceCountDefaultsKey
            )
        }
    }

    /// Empty string means "follow the current system / app language", and the
    /// preview block inherits the panel's localization. Any other value is an
    /// `AppLanguage.rawValue`, and the synthetic block renders its capsule names
    /// in that language while the rest of the panel keeps the real one. This is
    /// the whole point: side-by-side comparison of the same layout across two
    /// languages without leaving the panel.
    @Published var bluetoothListeningModePreviewLanguage: String {
        didSet {
            defaults.set(
                bluetoothListeningModePreviewLanguage,
                forKey: Self.bluetoothListeningModePreviewLanguageDefaultsKey
            )
        }
    }

    @Published var bluetoothSymbolScale: Double {
        didSet {
            let clamped = Self.clampedBluetoothSymbolScale(bluetoothSymbolScale)
            guard clamped == bluetoothSymbolScale else {
                bluetoothSymbolScale = clamped
                return
            }
            defaults.set(clamped, forKey: Self.bluetoothSymbolScaleDefaultsKey)
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

    @Published var ringStrokeStyle: RingStrokeStyle {
        didSet {
            defaults.set(ringStrokeStyle.rawValue, forKey: Self.ringStrokeStyleDefaultsKey)
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

    @Published var showsBluetoothDeviceList: Bool {
        didSet {
            defaults.set(
                showsBluetoothDeviceList,
                forKey: Self.showsBluetoothDeviceListDefaultsKey
            )
        }
    }

    @Published var maxVisibleBluetoothDevices: Int {
        didSet {
            let clamped = Self.clampedBluetoothDeviceLimit(maxVisibleBluetoothDevices)
            guard clamped == maxVisibleBluetoothDevices else {
                maxVisibleBluetoothDevices = clamped
                return
            }
            defaults.set(clamped, forKey: Self.maxVisibleBluetoothDevicesDefaultsKey)
        }
    }

    @Published private(set) var bluetoothDeviceOrder: [String] {
        didSet {
            defaults.set(bluetoothDeviceOrder, forKey: Self.bluetoothDeviceOrderDefaultsKey)
        }
    }

    @Published var hidesGhostBluetoothDevices: Bool {
        didSet {
            defaults.set(hidesGhostBluetoothDevices, forKey: Self.hidesGhostBluetoothDevicesDefaultsKey)
        }
    }

    @Published var hiddenBluetoothDeviceAddresses: Set<String> {
        didSet {
            defaults.set(Array(hiddenBluetoothDeviceAddresses), forKey: Self.hiddenBluetoothDeviceAddressesDefaultsKey)
        }
    }

    /// Normalized addresses of ghost devices the user has explicitly revealed,
    /// overriding the automatic ghost filter for those devices. Ghost devices are
    /// hidden by default, so this set starts empty; the user opens individual
    /// ones from Settings without showing every unpaired device at once.
    @Published var revealedGhostBluetoothDeviceAddresses: Set<String> {
        didSet {
            defaults.set(
                Array(revealedGhostBluetoothDeviceAddresses),
                forKey: Self.revealedGhostBluetoothDeviceAddressesDefaultsKey
            )
        }
    }

    /// The Bluetooth device whose icon replaces the network icon, by its
    /// normalized address. `nil` follows the current Bluetooth audio output —
    /// the original behavior and the default. Only the picker's highlight reads
    /// the address; the icon itself draws `bluetoothNetworkIconSymbolName`.
    @Published var bluetoothNetworkIconDeviceAddress: String? {
        didSet {
            defaults.set(
                bluetoothNetworkIconDeviceAddress,
                forKey: Self.bluetoothNetworkIconDeviceAddressDefaultsKey
            )
        }
    }

    /// The SF Symbol the picked device resolved to when it was chosen, stored
    /// so the icon pipeline needs no live device list: `iconAppearancePublisher`
    /// stays settings-only, and the menu bar and the Dock draw what the picker
    /// showed. Set together with the address through
    /// `setBluetoothNetworkIconDevice(address:symbolName:)`.
    @Published var bluetoothNetworkIconSymbolName: String? {
        didSet {
            defaults.set(
                bluetoothNetworkIconSymbolName,
                forKey: Self.bluetoothNetworkIconSymbolNameDefaultsKey
            )
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

    var bluetoothDeviceListOptions: BluetoothDeviceListOptions {
        BluetoothDeviceListOptions(
            showsList: showsBluetoothDeviceList,
            maxVisibleDevices: maxVisibleBluetoothDevices,
            order: bluetoothDeviceOrder,
            hidesGhostDevices: hidesGhostBluetoothDevices,
            hiddenDeviceAddresses: hiddenBluetoothDeviceAddresses,
            revealedGhostDeviceAddresses: revealedGhostBluetoothDeviceAddresses
        )
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

    func moveBluetoothDevices(
        fromOffsets source: IndexSet,
        toOffset destination: Int,
        in devices: [BluetoothDevice]
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
        bluetoothDeviceOrder = reorderedDevices.map {
            BluetoothBatteryReader.normalizedAddress($0.id)
        }
    }

    /// Hides or reveals a single device in the status-panel list, by its
    /// normalized address. Manual hides are independent of the automatic
    /// "hide devices not in System Settings" filter, so a device the user hides
    /// stays hidden whatever the profiler reports next.
    func setBluetoothDeviceHidden(_ address: String, hidden: Bool) {
        let key = BluetoothBatteryReader.normalizedAddress(address)
        guard !key.isEmpty else { return }
        if hidden {
            hiddenBluetoothDeviceAddresses.insert(key)
        } else {
            hiddenBluetoothDeviceAddresses.remove(key)
        }
    }

    /// Reveals or re-hides a single ghost device from the automatic
    /// "hide devices not in System Settings" filter, by its normalized address.
    /// Ghost devices are hidden by default; the user opens individual ones here
    /// without turning the global filter off (which would reveal every unpaired
    /// device at once). Revealing is a no-op for non-ghost devices.
    func setBluetoothGhostRevealed(_ address: String, revealed: Bool) {
        let key = BluetoothBatteryReader.normalizedAddress(address)
        guard !key.isEmpty else { return }
        if revealed {
            revealedGhostBluetoothDeviceAddresses.insert(key)
        } else {
            revealedGhostBluetoothDeviceAddresses.remove(key)
        }
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
            showsChargingEffect: showsChargingEffect,
            showsChargingBoltHeartbeat: showsChargingBoltHeartbeat,
            usesStatusColors: usesBatteryStatusColors,
            criticalThreshold: Int(batteryCriticalThreshold.rounded()),
            showsPercentageWhenConnected: showsPercentageWhenConnected,
            textScale: batterySymbolScale * BatteryIconOptions.defaultTextScale,
            ringStrokeScale: ringStrokeStyle.scale
        )
    }

    var connectionIconOptions: ConnectionIconOptions {
        ConnectionIconOptions(
            showsWiFiIconForEthernet: showsWiFiIconForEthernet,
            showsWiFiIconForHotspot: showsWiFiIconForHotspot,
            showsWiFiIconForTemporaryConnection: showsWiFiIconForTemporaryConnection,
            showsWiFiIconForInternetSharing: showsWiFiIconForInternetSharing,
            showsBatteryPercentageInConnectionSlot: showsBatteryPercentageInConnectionSlot,
            wifiScale: wifiSymbolScale
        )
    }

    var bluetoothAudioIconOptions: BluetoothAudioIconOptions {
        BluetoothAudioIconOptions(
            replacesNetworkIcon: replacesNetworkIconWithBluetoothAudio,
            usesVolumeColor: usesBluetoothAudioVolumeColor,
            prioritizesNetworkErrors: prioritizesNetworkErrorsOverBluetoothAudio,
            symbolScale: bluetoothSymbolScale,
            networkIconSymbolOverride: bluetoothNetworkIconSymbolName
        )
    }

    /// Picks which Bluetooth device's icon replaces the network icon.
    ///
    /// The address and the resolved symbol are stored together so the choice is
    /// atomic: the picker highlights by address while the icon draws the symbol
    /// the device resolved to at pick time. `nil` for both returns to the
    /// default — the current Bluetooth audio output.
    func setBluetoothNetworkIconDevice(address: String?, symbolName: String?) {
        bluetoothNetworkIconDeviceAddress = address
        bluetoothNetworkIconSymbolName = symbolName
    }

    var volumeIconOptions: VolumeIconOptions {
        VolumeIconOptions(
            displayStyle: volumeDisplayStyle,
            ringStrokeScale: ringStrokeStyle.scale
        )
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
        let storedBluetoothDeviceLimit = (defaults.object(
            forKey: Self.maxVisibleBluetoothDevicesDefaultsKey
        ) as? NSNumber)?.intValue
        let storedBluetoothDeviceOrder = defaults.stringArray(
            forKey: Self.bluetoothDeviceOrderDefaultsKey
        ) ?? []
        let storedHidesGhostBluetoothDevices = defaults.object(
            forKey: Self.hidesGhostBluetoothDevicesDefaultsKey
        ) as? Bool
        let storedHiddenBluetoothDeviceAddresses = Set(
            defaults.stringArray(forKey: Self.hiddenBluetoothDeviceAddressesDefaultsKey) ?? []
        )
        let storedRevealedGhostBluetoothDeviceAddresses = Set(
            defaults.stringArray(forKey: Self.revealedGhostBluetoothDeviceAddressesDefaultsKey) ?? []
        )
        let storedRefreshInterval = (defaults.object(forKey: Self.refreshIntervalDefaultsKey) as? NSNumber)?.doubleValue
        let storedBluetoothSymbolScale = (defaults.object(forKey: Self.bluetoothSymbolScaleDefaultsKey) as? NSNumber)?.doubleValue
        let storedWifiSymbolScale = (defaults.object(forKey: Self.wifiSymbolScaleDefaultsKey) as? NSNumber)?.doubleValue
        let storedVolumeDisplayStyle = defaults.string(forKey: Self.volumeDisplayStyleDefaultsKey)
        let storedRingStrokeStyle = defaults.string(forKey: Self.ringStrokeStyleDefaultsKey)
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
        self.showsChargingEffect = defaults.object(
            forKey: Self.showsChargingEffectDefaultsKey
        ) as? Bool ?? true
        self.showsChargingBoltHeartbeat = defaults.object(
            forKey: Self.showsChargingBoltHeartbeatDefaultsKey
        ) as? Bool ?? true
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
        self.showsBatteryPercentageInConnectionSlot = defaults.object(
            forKey: Self.showsBatteryPercentageInConnectionSlotDefaultsKey
        ) as? Bool ?? false
        self.replacesNetworkIconWithBluetoothAudio = defaults.object(
            forKey: Self.replacesNetworkIconWithBluetoothAudioDefaultsKey
        ) as? Bool ?? false
        self.usesBluetoothAudioVolumeColor = defaults.object(
            forKey: Self.usesBluetoothAudioVolumeColorDefaultsKey
        ) as? Bool ?? false
        self.prioritizesNetworkErrorsOverBluetoothAudio = defaults.object(
            forKey: Self.prioritizesNetworkErrorsOverBluetoothAudioDefaultsKey
        ) as? Bool ?? true
        self.showsBluetoothBatteryLevels = defaults.object(
            forKey: Self.showsBluetoothBatteryLevelsDefaultsKey
        ) as? Bool ?? true
        self.showsNearbyBluetoothBatteryDevices = defaults.object(
            forKey: Self.showsNearbyBluetoothBatteryDevicesDefaultsKey
        ) as? Bool ?? false
        self.showsMobileDeviceBatteryLevels = defaults.object(
            forKey: Self.showsMobileDeviceBatteryLevelsDefaultsKey
        ) as? Bool ?? false
        self.previewsBluetoothListeningMode = defaults.object(
            forKey: Self.previewsBluetoothListeningModeDefaultsKey
        ) as? Bool ?? false
        self.bluetoothListeningModePreviewDeviceName = defaults.string(
            forKey: Self.bluetoothListeningModePreviewDeviceNameDefaultsKey
        ) ?? ""
        let storedPreviewCount = defaults.object(
            forKey: Self.bluetoothListeningModePreviewDeviceCountDefaultsKey
        ) as? Int
        let previewCountRange = Self.bluetoothListeningModePreviewDeviceCountRange
        self.bluetoothListeningModePreviewDeviceCount = min(
            max(storedPreviewCount ?? Self.defaultBluetoothListeningModePreviewDeviceCount,
                previewCountRange.lowerBound),
            previewCountRange.upperBound
        )
        self.bluetoothListeningModePreviewLanguage = defaults.string(
            forKey: Self.bluetoothListeningModePreviewLanguageDefaultsKey
        ) ?? ""
        self.bluetoothSymbolScale = Self.clampedBluetoothSymbolScale(
            storedBluetoothSymbolScale ?? Self.defaultBluetoothSymbolScale
        )
        self.wifiSymbolScale = Self.clampedWifiSymbolScale(
            storedWifiSymbolScale ?? Self.defaultWifiSymbolScale
        )
        self.volumeDisplayStyle = storedVolumeDisplayStyle
            .flatMap(VolumeDisplayStyle.init(rawValue:))
            ?? Self.defaultVolumeDisplayStyle
        self.ringStrokeStyle = storedRingStrokeStyle
            .flatMap(RingStrokeStyle.init(rawValue:))
            ?? Self.defaultRingStrokeStyle
        self.refreshIntervalSeconds = Self.clampedRefreshInterval(
            storedRefreshInterval ?? Self.defaultRefreshIntervalSeconds
        )
        self.maxVisibleOutputDevices = Self.clampedOutputDeviceLimit(
            storedOutputDeviceLimit ?? Self.defaultMaxVisibleOutputDevices
        )
        self.showsBluetoothDeviceList = defaults.object(
            forKey: Self.showsBluetoothDeviceListDefaultsKey
        ) as? Bool ?? true
        self.maxVisibleBluetoothDevices = Self.clampedBluetoothDeviceLimit(
            storedBluetoothDeviceLimit ?? Self.defaultMaxVisibleBluetoothDevices
        )
        self.bluetoothDeviceOrder = storedBluetoothDeviceOrder
        self.hidesGhostBluetoothDevices = storedHidesGhostBluetoothDevices ?? true
        self.hiddenBluetoothDeviceAddresses = storedHiddenBluetoothDeviceAddresses
        self.revealedGhostBluetoothDeviceAddresses = storedRevealedGhostBluetoothDeviceAddresses
        self.bluetoothNetworkIconDeviceAddress = defaults.string(
            forKey: Self.bluetoothNetworkIconDeviceAddressDefaultsKey
        )
        self.bluetoothNetworkIconSymbolName = defaults.string(
            forKey: Self.bluetoothNetworkIconSymbolNameDefaultsKey
        )
        self.alwaysShowsAllOutputDevices = defaults.object(
            forKey: Self.alwaysShowsAllOutputDevicesDefaultsKey
        ) as? Bool ?? false
        self.outputDeviceOrder = storedOutputDeviceOrder
        self.popupSectionOrder = Self.sanitizedPopupSectionOrder(
            storedPopupSectionOrder
        )
        let hasIntroducedVPN = defaults.bool(
            forKey: Self.vpnPopupSectionIntroducedDefaultsKey
        )
        let migratedEnabledPopupSections = Self.sanitizedEnabledPopupSections(
            storedEnabledPopupSections,
            hasIntroducedVPN: hasIntroducedVPN
        )
        self.enabledPopupSections = migratedEnabledPopupSections
        if !hasIntroducedVPN {
            // The migration has to be written back by hand: `didSet` does not run
            // for an assignment made inside `init`, so a migrated list that was
            // left only in memory would be rebuilt from the stored list — which
            // lacks `.vpn` — on the next launch, and the row would vanish again.
            if storedEnabledPopupSections != nil {
                defaults.set(
                    migratedEnabledPopupSections.map(\.rawValue).sorted(),
                    forKey: Self.enabledPopupSectionsDefaultsKey
                )
            }
            defaults.set(true, forKey: Self.vpnPopupSectionIntroducedDefaultsKey)
        }
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

    static func clampedBluetoothSymbolScale(_ value: Double) -> Double {
        guard value.isFinite else { return defaultBluetoothSymbolScale }
        return min(
            bluetoothSymbolScaleRange.upperBound,
            max(bluetoothSymbolScaleRange.lowerBound, value)
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

    static func clampedBluetoothDeviceLimit(_ value: Int) -> Int {
        min(bluetoothDeviceLimitRange.upperBound, max(bluetoothDeviceLimitRange.lowerBound, value))
    }

    static func sanitizedPopupSectionOrder(_ rawValues: [String]) -> [PopupSection] {
        var seen: Set<PopupSection> = []
        let storedSections = rawValues
            .compactMap(PopupSection.init(rawValue:))
            .filter { seen.insert($0).inserted }
        return storedSections + PopupSection.allCases.filter { !seen.contains($0) }
    }

    /// Adds `.vpn` to a list that predates the row, once.
    ///
    /// A stored list is the user's own selection, so the default set cannot
    /// reach it and an upgrade would otherwise leave the new row switched off
    /// for everyone who already had a list. `hasIntroducedVPN` makes the pass
    /// one-shot: after it has run, a stored list without `.vpn` means the user
    /// turned the row off, and that choice is what gets returned.
    static func sanitizedEnabledPopupSections(
        _ rawValues: [String]?,
        hasIntroducedVPN: Bool
    ) -> Set<PopupSection> {
        guard let rawValues else {
            return defaultEnabledPopupSections
        }
        var sections = Set(rawValues.compactMap(PopupSection.init(rawValue:)))
        if !hasIntroducedVPN {
            sections.insert(.vpn)
        }
        return sections
    }
}
