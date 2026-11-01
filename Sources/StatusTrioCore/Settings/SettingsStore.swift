import AppKit
import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    static let hasCompletedIconGuideOnboardingDefaultsKey = "hasCompletedIconGuideOnboarding.v1"
    static let hasSeenIconGuideDefaultsKey = "hasSeenIconGuide"
    static let sharesAnonymousAnalyticsDefaultsKey = "sharesAnonymousAnalytics"
    static let telemetryConsentVersionDefaultsKey = "telemetryConsentVersion"
    static let statusPanelShortcutDefaultsKey = "statusPanelShortcut.v1"
    private static let sparkleHasLaunchedBeforeDefaultsKey = "SUHasLaunchedBefore"

    static let iconSizeRange: ClosedRange<Double> = 16...36
    static let defaultIconSize: Double = 24
    static let iconSizeDefaultsKey = "menuBarIconSize"

    static let batteryCriticalThresholdRange: ClosedRange<Double> = 0...100
    static let defaultBatteryCriticalThreshold: Double = 20
    /// The ring closes at the level the user picks. The floor keeps the arc a
    /// usable fraction of the circle instead of a hairline at 1%.
    static let batteryFullThresholdRange: ClosedRange<Double> = 50...100
    static let defaultBatteryFullThreshold: Double = Double(BatteryIconOptions.defaultFullThreshold)
    /// The charge limit restored when the user cancels Charge to Full Now.
    /// 100 means "no limit", so cancelling re-enables normal charging to 100%.
    static let chargeToFullRestoreLimitRange: ClosedRange<Double> = 80...100
    static let defaultChargeToFullRestoreLimit: Double = 100
    static let chargeToFullRestoreLimitDefaultsKey = "chargeToFullRestoreLimit"
    static let batterySymbolScaleRange: ClosedRange<Double> = 0.9...1.1
    static let defaultBatterySymbolScale: Double = 1
    static let showsBatteryPercentageDefaultsKey = "showsBatteryPercentage"
    static let showsBatteryPowerFlowDefaultsKey = "showsBatteryPowerFlow"
    static let showsBatteryPowerInfoBarDefaultsKey = "showsBatteryPowerInfoBar"
    static let showsHighEnergyAppsDefaultsKey = "showsHighEnergyApps"
    static let highEnergyAppsRefreshIntervalDefaultsKey = "highEnergyAppsRefreshIntervalSeconds"
    static let highEnergyAppsRefreshIntervalRange: ClosedRange<Double> = 10...60
    static let defaultHighEnergyAppsRefreshIntervalSeconds: Double = 10
    static let showsChargeToFullNowButtonDefaultsKey = "showsChargeToFullNowButton"
    static let showsChargingIndicatorDefaultsKey = "showsChargingIndicator"
    /// Legacy single-surface preference retained only for migration.
    static let showsChargingEffectDefaultsKey = "showsChargingEffect"
    static let showsMenuBarChargingEffectDefaultsKey = "showsMenuBarChargingEffect"
    static let showsDockChargingEffectDefaultsKey = "showsDockChargingEffect"
    static let showsChargingBoltHeartbeatDefaultsKey = "showsChargingBoltHeartbeat"
    static let showsPercentageWhenConnectedDefaultsKey = "showsPercentageWhenConnected"
    static let usesBatteryStatusColorsDefaultsKey = "usesBatteryStatusColors"
    static let batteryStatusColorsChargingDefaultsKey = "batteryStatusColors.charging"
    static let batteryStatusColorsLowPowerDefaultsKey = "batteryStatusColors.lowPower"
    static let batteryStatusColorsCriticalDefaultsKey = "batteryStatusColors.critical"
    static let batteryCriticalThresholdDefaultsKey = "batteryCriticalThreshold"
    static let batteryFullThresholdDefaultsKey = "batteryFullThreshold"
    static let batterySymbolScaleDefaultsKey = "batterySymbolScale"
    static let showsWiFiIconForEthernetDefaultsKey = "showsWiFiIconForEthernet"
    static let showsWiFiIconForHotspotDefaultsKey = "showsWiFiIconForHotspot"
    static let showsWiFiIconForTemporaryConnectionDefaultsKey = "showsWiFiIconForTemporaryConnection"
    static let showsWiFiIconForInternetSharingDefaultsKey = "showsWiFiIconForInternetSharing"
    /// Draws the private LAN address on the network row's second line. Off by
    /// default: the address is a diagnostic, not something every panel needs.
    static let showsLocalIPAddressDefaultsKey = "showsLocalIPAddress"
    /// Migration-only: superseded by `connectionCenterSource`. Read once at
    /// launch, then removed so it can never override a later selection.
    static let showsBatteryPercentageInConnectionSlotDefaultsKey = "showsBatteryPercentageInConnectionSlot"
    /// Raw value of `ConnectionCenterSource`. Missing or unknown values decode
    /// to `.automatic`, so a downgrade or corrupted default never changes the
    /// shipped icon behaviour.
    static let connectionCenterSourceDefaultsKey = "connectionCenterSource"
    static let prioritizesNetworkErrorsOverInputSourceDefaultsKey = "prioritizesNetworkErrorsOverInputSource"
    static let replacesNetworkIconWithBluetoothAudioDefaultsKey = "replacesNetworkIconWithBluetoothAudio"
    static let usesBluetoothAudioVolumeColorDefaultsKey = "usesBluetoothAudioVolumeColor"
    static let prioritizesNetworkErrorsOverBluetoothAudioDefaultsKey = "prioritizesNetworkErrorsOverBluetoothAudio"
    static let showsBluetoothBatteryLevelsDefaultsKey = "showsBluetoothBatteryLevels"
    static let showsBluetoothPowerControlDefaultsKey = "showsBluetoothPowerControl"
    static let controlsLowPowerModeDefaultsKey = "controlsLowPowerMode"
    static let showsNearbyBluetoothBatteryDevicesDefaultsKey = "showsNearbyBluetoothBatteryDevices"
    static let showsMobileDeviceBatteryLevelsDefaultsKey = "showsMobileDeviceBatteryLevels"
    static let showsAppleDevicesAndBatteryDefaultsKey = "showsAppleDevicesAndBattery"
    static let refreshesAppleBatteriesInBackgroundDefaultsKey = "refreshesAppleBatteriesInBackground"
    static let appleBatteryRefreshIntervalMinutesDefaultsKey = "appleBatteryRefreshIntervalMinutes"
    static let appleBatteryRefreshIntervalMinutesRange = 1...10
    static let defaultAppleBatteryRefreshIntervalMinutes = 1
    static let appleDeviceSelectionsDefaultsKey = "appleDeviceSelections"
    static let appleDeviceSettingsMigrationVersionDefaultsKey = "appleDeviceSettingsMigrationVersion"
    static let archivedLegacyNearbyBLESelectionsDefaultsKey = "archivedLegacyNearbyBLESelections"
    static let trustedAppleDeviceMetadataDefaultsKey = "trustedAppleDeviceMetadata.v1"
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
    static let bluetoothAudioIconChoiceDefaultsKey = "bluetoothAudioIconChoice"
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
    static let inputDeviceLimitRange: ClosedRange<Int> = 1...20
    static let defaultMaxVisibleInputDevices = 5
    static let maxVisibleInputDevicesDefaultsKey = "maxVisibleInputDevices"
    static let alwaysShowsAllInputDevicesDefaultsKey = "alwaysShowsAllInputDevices"
    static let defaultMaxVisibleBluetoothDevices = 5
    static let maxVisibleBluetoothDevicesDefaultsKey = "maxVisibleBluetoothDevices"
    static let showsBluetoothDeviceListDefaultsKey = "showsBluetoothDeviceList"
    static let bluetoothDeviceOrderDefaultsKey = "bluetoothDeviceOrder"
    static let hidesGhostBluetoothDevicesDefaultsKey = "hidesGhostBluetoothDevices"
    static let hiddenBluetoothDeviceAddressesDefaultsKey = "hiddenBluetoothDeviceAddresses"
    static let revealedGhostBluetoothDeviceAddressesDefaultsKey = "revealedGhostBluetoothDeviceAddresses"
    static let nearbyBLESelectionsDefaultsKey = "nearbyBLESelections"
    /// Named BLE UUID metadata is retained independently of temporary discovery.
    static let nearbyBLEConsentDefaultsKey = "nearbyBLEConsent.v1"
    static let bluetoothNetworkIconDeviceAddressDefaultsKey = "bluetoothNetworkIconDeviceAddress"
    static let bluetoothNetworkIconSymbolNameDefaultsKey = "bluetoothNetworkIconSymbolName"
    static let bluetoothDeviceLimitRange: ClosedRange<Int> = 1...20
    static let alwaysShowsAllOutputDevicesDefaultsKey = "alwaysShowsAllOutputDevices"
    static let outputDeviceOrderDefaultsKey = "outputDeviceOrder"
    static let hiddenOutputDeviceUIDsDefaultsKey = "hiddenOutputDeviceUIDs"
    static let inputDeviceOrderDefaultsKey = "inputDeviceOrder"
    static let hiddenInputDeviceUIDsDefaultsKey = "hiddenInputDeviceUIDs"
    static let externalVolumeConfigurationsDefaultsKey = "externalVolumeConfigurations.v1"
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

    @Published private(set) var sharesAnonymousAnalytics: Bool
    @Published private(set) var telemetryConsentVersion: Int
    @Published var statusPanelShortcut: StatusPanelShortcut? {
        didSet {
            guard let statusPanelShortcut,
                  let data = try? JSONEncoder().encode(statusPanelShortcut) else {
                defaults.removeObject(forKey: Self.statusPanelShortcutDefaultsKey)
                return
            }
            defaults.set(data, forKey: Self.statusPanelShortcutDefaultsKey)
        }
    }
    private let telemetryConsentSubject = PassthroughSubject<TelemetryConsent, Never>()

    var canShareAnonymousAnalytics: Bool {
        telemetryConsentSnapshot.canShareAnonymousAnalytics
    }

    var telemetryConsentSnapshot: TelemetryConsent {
        TelemetryConsent(
            version: telemetryConsentVersion,
            sharesAnonymousAnalytics: sharesAnonymousAnalytics
        )
    }

    var telemetryConsentUpdates: AnyPublisher<TelemetryConsent, Never> {
        telemetryConsentSubject.eraseToAnyPublisher()
    }

    func completeTelemetryConsent(sharesAnalytics: Bool) {
        guard let recordedVersion = consentVersionToRecord(grants: sharesAnalytics) else { return }

        // Persist both values before emitting one coherent snapshot. @Published
        // emits before didSet, so observers must use this explicit publisher.
        defaults.set(sharesAnalytics, forKey: Self.sharesAnonymousAnalyticsDefaultsKey)
        defaults.set(recordedVersion, forKey: Self.telemetryConsentVersionDefaultsKey)
        sharesAnonymousAnalytics = sharesAnalytics
        telemetryConsentVersion = recordedVersion
        telemetryConsentSubject.send(telemetryConsentSnapshot)
    }

    /// The version to store alongside a new analytics answer, or `nil` when the
    /// answer must be dropped.
    ///
    /// A stored version newer than this build means the user answered a newer
    /// prompt and then went back to an older build. Granting is refused then —
    /// this build cannot speak for a prompt it never showed — but withdrawing
    /// is not: consent has to stay revocable, otherwise the analytics toggle
    /// silently refuses to move. A withdrawal keeps the stored version, so the
    /// newer build still sees the answer it recorded together with `false`.
    private func consentVersionToRecord(grants: Bool) -> Int? {
        if telemetryConsentVersion > TelemetryConsent.currentVersion {
            return grants ? nil : telemetryConsentVersion
        }
        return TelemetryConsent.currentVersion
    }

    func setSharesAnonymousAnalytics(_ enabled: Bool) {
        completeTelemetryConsent(sharesAnalytics: enabled)
    }

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

    /// The single switch for the details page's power flow diagram. When on it
    /// draws the full diagram (input, battery, breakdown/system); when off the
    /// diagram is hidden. The old per-rail switches were folded into this one.
    @Published var showsBatteryPowerFlow: Bool {
        didSet { defaults.set(showsBatteryPowerFlow, forKey: Self.showsBatteryPowerFlowDefaultsKey) }
    }
    /// Provisional: shows input/battery/system power under the panel's battery
    /// module. Off by default; not yet an accepted specification.
    @Published var showsBatteryPowerInfoBar: Bool {
        didSet { defaults.set(showsBatteryPowerInfoBar, forKey: Self.showsBatteryPowerInfoBarDefaultsKey) }
    }
    @Published var showsHighEnergyApps: Bool {
        didSet { defaults.set(showsHighEnergyApps, forKey: Self.showsHighEnergyAppsDefaultsKey) }
    }
    @Published var highEnergyAppsRefreshIntervalSeconds: Double {
        didSet {
            let clamped = Self.clampedHighEnergyAppsRefreshInterval(highEnergyAppsRefreshIntervalSeconds)
            guard clamped == highEnergyAppsRefreshIntervalSeconds else {
                highEnergyAppsRefreshIntervalSeconds = clamped
                return
            }
            defaults.set(clamped, forKey: Self.highEnergyAppsRefreshIntervalDefaultsKey)
        }
    }

    var batteryPowerDisplayOptions: BatteryPowerDisplayOptions {
        // One switch drives every rail; the reader still only samples what the
        // diagram needs.
        BatteryPowerDisplayOptions(
            showsInput: showsBatteryPowerFlow,
            showsCharging: showsBatteryPowerFlow,
            showsSystem: showsBatteryPowerFlow,
            showsBreakdown: showsBatteryPowerFlow
        )
    }

    @Published var showsChargeToFullNowButton: Bool {
        didSet {
            defaults.set(
                showsChargeToFullNowButton,
                forKey: Self.showsChargeToFullNowButtonDefaultsKey
            )
        }
    }

    @Published var showsChargingIndicator: Bool {
        didSet {
            defaults.set(showsChargingIndicator, forKey: Self.showsChargingIndicatorDefaultsKey)
        }
    }

    @Published var showsMenuBarChargingEffect: Bool {
        didSet {
            defaults.set(
                showsMenuBarChargingEffect,
                forKey: Self.showsMenuBarChargingEffectDefaultsKey
            )
            if !showsMenuBarChargingEffect && !showsDockChargingEffect {
                testsChargingEffect = false
            }
        }
    }

    @Published var showsDockChargingEffect: Bool {
        didSet {
            defaults.set(
                showsDockChargingEffect,
                forKey: Self.showsDockChargingEffectDefaultsKey
            )
            if !showsMenuBarChargingEffect && !showsDockChargingEffect {
                testsChargingEffect = false
            }
        }
    }

    /// The shared scene carries the effect when either surface can animate.
    /// Each renderer removes it independently for a surface that is switched off.
    var showsChargingEffect: Bool {
        get { showsMenuBarChargingEffect || showsDockChargingEffect }
        set {
            showsMenuBarChargingEffect = newValue
            showsDockChargingEffect = newValue
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
        testsChargingEffect = enabled
    }

    /// Development-only: turns on the synthetic charging input without touching
    /// the animation preference, so a measurement run can compare the animation
    /// on and off against the same charging state. See
    /// `ChargingEffectTestMode.forceChargingInputEnvironmentKey`.
    func setChargingEffectTestInputEnabled(_ enabled: Bool) {
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

    /// Per-role colour overrides for the charging, low-power and critical states.
    /// Edited in place by the settings UI, so a nested mutation still triggers
    /// this `didSet` and publishes one fresh value.
    @Published var batteryStatusColors: BatteryStatusColors {
        didSet {
            guard batteryStatusColors != oldValue else { return }
            defaults.set(
                batteryStatusColors.charging.storageValue,
                forKey: Self.batteryStatusColorsChargingDefaultsKey
            )
            defaults.set(
                batteryStatusColors.lowPower.storageValue,
                forKey: Self.batteryStatusColorsLowPowerDefaultsKey
            )
            defaults.set(
                batteryStatusColors.critical.storageValue,
                forKey: Self.batteryStatusColorsCriticalDefaultsKey
            )
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

    /// The level at which the battery ring counts as full (#105).
    ///
    /// Charge limiting holds a plugged-in battery below 100%, so a ring scaled
    /// to a fixed 100% never closes. Rescaling the arc to this level makes the
    /// ring close at the cap the user actually reaches.
    @Published var batteryFullThreshold: Double {
        didSet {
            let clamped = Self.clampedBatteryFullThreshold(batteryFullThreshold)
            guard clamped == batteryFullThreshold else {
                batteryFullThreshold = clamped
                return
            }
            defaults.set(clamped, forKey: Self.batteryFullThresholdDefaultsKey)
        }
    }

    /// The charge limit restored when the user cancels Charge to Full Now.
    ///
    /// macOS removes the persisted limit while its own temporary override runs,
    /// so an explicit setting is more reliable than guessing the old value.
    /// 100 means "no limit": cancelling simply resumes normal charging to 100%.
    @Published var chargeToFullRestoreLimit: Double {
        didSet {
            let clamped = Self.clampedChargeToFullRestoreLimit(
                chargeToFullRestoreLimit
            )
            guard clamped == chargeToFullRestoreLimit else {
                chargeToFullRestoreLimit = clamped
                return
            }
            defaults.set(
                clamped,
                forKey: Self.chargeToFullRestoreLimitDefaultsKey
            )
        }
    }

    /// Test seam: a recorded plist to read instead of the live one, so the
    /// follow path is tested against a known limit rather than whatever this
    /// Mac happens to be set to. `nil` in the app, which reads the real file.
    var chargeLimitURLForTesting: URL?

    /// Whether the macOS charge limit can be read at all (#105).
    ///
    /// The value lives in a private, root-owned plist that no public API
    /// exposes. It is readable on an unsandboxed build, but it is not guaranteed
    /// to be there, so the button that fills the slider in from it is hidden
    /// behind this rather than failing silently when pressed.
    var canReadSystemChargeLimit: Bool {
        if let url = chargeLimitURLForTesting {
            return SystemChargeLimitReader.chargeLimit(from: url) != nil
        }
        return SystemChargeLimitReader.chargeLimit() != nil
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

    @Published var showsLocalIPAddress: Bool {
        didSet {
            defaults.set(
                showsLocalIPAddress,
                forKey: Self.showsLocalIPAddressDefaultsKey
            )
        }
    }

    @Published var connectionCenterSource: ConnectionCenterSource {
        didSet {
            defaults.set(
                connectionCenterSource.rawValue,
                forKey: Self.connectionCenterSourceDefaultsKey
            )
        }
    }

    @Published var prioritizesNetworkErrorsOverInputSource: Bool {
        didSet {
            defaults.set(
                prioritizesNetworkErrorsOverInputSource,
                forKey: Self.prioritizesNetworkErrorsOverInputSourceDefaultsKey
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

    /// The Bluetooth radio switch uses private IOBluetooth symbols, but needs
    /// no helper or additional permission. It is on by default and only hides
    /// the panel affordance when explicitly turned off.
    @Published var showsBluetoothPowerControl: Bool {
        didSet {
            defaults.set(
                showsBluetoothPowerControl,
                forKey: Self.showsBluetoothPowerControlDefaultsKey
            )
        }
    }

    /// Nil on first launch, allowing adoption of an existing helper registration.
    var savedLowPowerModeControlPreference: Bool? {
        defaults.object(forKey: Self.controlsLowPowerModeDefaultsKey) as? Bool
    }

    @Published var controlsLowPowerMode: Bool {
        didSet {
            defaults.set(controlsLowPowerMode, forKey: Self.controlsLowPowerModeDefaultsKey)
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

    @Published var showsAppleDevicesAndBattery: Bool {
        didSet { defaults.set(showsAppleDevicesAndBattery, forKey: Self.showsAppleDevicesAndBatteryDefaultsKey) }
    }

    @Published var refreshesAppleBatteriesInBackground: Bool {
        didSet {
            defaults.set(
                refreshesAppleBatteriesInBackground,
                forKey: Self.refreshesAppleBatteriesInBackgroundDefaultsKey
            )
        }
    }

    @Published var appleBatteryRefreshIntervalMinutes: Int {
        didSet {
            let clamped = Self.clampedAppleBatteryRefreshInterval(appleBatteryRefreshIntervalMinutes)
            guard clamped == appleBatteryRefreshIntervalMinutes else {
                appleBatteryRefreshIntervalMinutes = clamped
                return
            }
            defaults.set(clamped, forKey: Self.appleBatteryRefreshIntervalMinutesDefaultsKey)
        }
    }

    @Published private(set) var archivedLegacyNearbyBLESelections: [NearbyBLEDeviceSelection]

    @Published private(set) var trustedAppleDeviceMetadata: [AppleDeviceCandidate] {
        didSet {
            guard let data = try? JSONEncoder().encode(trustedAppleDeviceMetadata) else { return }
            defaults.set(data, forKey: Self.trustedAppleDeviceMetadataDefaultsKey)
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

    @Published var bluetoothAudioIconChoiceRawValue: String {
        didSet { defaults.set(bluetoothAudioIconChoiceRawValue, forKey: Self.bluetoothAudioIconChoiceDefaultsKey) }
    }

    var bluetoothAudioIconChoice: BluetoothAudioIconChoice {
        get {
            BluetoothAudioIconChoice.persisted(bluetoothAudioIconChoiceRawValue) { symbol in
                NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil
            }
        }
        set { bluetoothAudioIconChoiceRawValue = newValue.rawValue }
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

    @Published var maxVisibleInputDevices: Int {
        didSet {
            let clamped = Self.clampedInputDeviceLimit(maxVisibleInputDevices)
            guard clamped == maxVisibleInputDevices else {
                maxVisibleInputDevices = clamped
                return
            }
            defaults.set(clamped, forKey: Self.maxVisibleInputDevicesDefaultsKey)
        }
    }

    @Published var alwaysShowsAllInputDevices: Bool {
        didSet {
            defaults.set(
                alwaysShowsAllInputDevices,
                forKey: Self.alwaysShowsAllInputDevicesDefaultsKey
            )
        }
    }

    @Published private(set) var outputDeviceOrder: [String] {
        didSet {
            defaults.set(outputDeviceOrder, forKey: Self.outputDeviceOrderDefaultsKey)
        }
    }

    /// UIDs of output devices the user unchecked in Settings. The status panel
    /// leaves them out unless one is the active output.
    @Published private(set) var hiddenOutputDeviceUIDs: Set<String> {
        didSet {
            defaults.set(Array(hiddenOutputDeviceUIDs), forKey: Self.hiddenOutputDeviceUIDsDefaultsKey)
        }
    }

    @Published private(set) var inputDeviceOrder: [String] {
        didSet {
            defaults.set(inputDeviceOrder, forKey: Self.inputDeviceOrderDefaultsKey)
        }
    }

    /// UIDs of input devices the user unchecked in Settings. The Audio Input
    /// section leaves them out unless one is the current input.
    @Published private(set) var hiddenInputDeviceUIDs: Set<String> {
        didSet {
            defaults.set(Array(hiddenInputDeviceUIDs), forKey: Self.hiddenInputDeviceUIDsDefaultsKey)
        }
    }

    @Published private(set) var externalVolumeConfigurations: [String: ExternalVolumeConfiguration] {
        didSet {
            guard !externalVolumeConfigurations.isEmpty,
                  let data = try? JSONEncoder().encode(externalVolumeConfigurations)
            else {
                defaults.removeObject(forKey: Self.externalVolumeConfigurationsDefaultsKey)
                return
            }
            defaults.set(data, forKey: Self.externalVolumeConfigurationsDefaultsKey)
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

    @Published private(set) var nearbyBLESelections: [NearbyBLEDeviceSelection] {
        didSet {
            guard let data = try? JSONEncoder().encode(nearbyBLESelections) else { return }
            defaults.set(data, forKey: Self.nearbyBLEConsentDefaultsKey)
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

    var visibleInputDeviceLimit: Int? {
        alwaysShowsAllInputDevices ? nil : maxVisibleInputDevices
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

    var outputDeviceListPreferences: AudioOutputListPreferences {
        AudioOutputListPreferences(
            order: outputDeviceOrder,
            hiddenUIDs: hiddenOutputDeviceUIDs,
            visibleLimit: visibleOutputDeviceLimit
        )
    }

    var inputDeviceListPreferences: AudioInputListPreferences {
        AudioInputListPreferences(
            order: inputDeviceOrder,
            hiddenUIDs: hiddenInputDeviceUIDs,
            visibleLimit: visibleInputDeviceLimit
        )
    }

    /// The Settings order list, in the saved order. Hidden devices keep their
    /// place here; only the status panel filters them out.
    func orderedOutputDevices(_ devices: [AudioOutputDevice]) -> [AudioOutputDevice] {
        OutputDeviceListPresentation.orderedDevices(devices, using: outputDeviceOrder)
    }

    func externalVolumeConfiguration(for uid: String) -> ExternalVolumeConfiguration {
        let uid = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty else { return .default }
        return externalVolumeConfigurations[uid] ?? .default
    }

    func setExternalVolumeConfiguration(
        _ configuration: ExternalVolumeConfiguration,
        for uid: String
    ) {
        let uid = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty else { return }

        var updated = externalVolumeConfigurations
        if let sanitized = configuration.sanitized(), sanitized != .default {
            updated[uid] = sanitized
        } else {
            updated.removeValue(forKey: uid)
        }
        guard updated != externalVolumeConfigurations else { return }
        externalVolumeConfigurations = updated
    }

    func moveOutputDevices(
        fromOffsets source: IndexSet,
        toOffset destination: Int,
        in devices: [AudioOutputDevice]
    ) {
        guard let reordered = Self.movedDeviceUIDs(
            devices.map(\.uid),
            fromOffsets: source,
            toOffset: destination
        ) else { return }
        outputDeviceOrder = Self.mergedDeviceOrder(reordered, previous: outputDeviceOrder)
    }

    /// Shows or hides one output device in the status panel. Hiding never
    /// reorders the list, so the saved order stays independent of the checkbox.
    func setOutputDeviceHidden(_ uid: String, hidden: Bool) {
        guard !uid.isEmpty else { return }
        if hidden {
            hiddenOutputDeviceUIDs.insert(uid)
        } else {
            hiddenOutputDeviceUIDs.remove(uid)
        }
    }

    func moveInputDevices(
        fromOffsets source: IndexSet,
        toOffset destination: Int,
        in devices: [AudioInputDevice]
    ) {
        guard let reordered = Self.movedDeviceUIDs(
            devices.map(\.uid),
            fromOffsets: source,
            toOffset: destination
        ) else { return }
        inputDeviceOrder = Self.mergedDeviceOrder(reordered, previous: inputDeviceOrder)
    }

    /// Shows or hides one input device in the Audio Input section. Hiding never
    /// reorders the list, so the saved order stays independent of the checkbox.
    func setInputDeviceHidden(_ uid: String, hidden: Bool) {
        guard !uid.isEmpty else { return }
        if hidden {
            hiddenInputDeviceUIDs.insert(uid)
        } else {
            hiddenInputDeviceUIDs.remove(uid)
        }
    }

    /// The UIDs of `devices` after a drag, or `nil` for an out-of-range move.
    /// Devices without a UID take part in the move but are not saved.
    private static func movedDeviceUIDs(
        _ uids: [String?],
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) -> [String]? {
        guard !source.isEmpty,
              source.allSatisfy({ uids.indices.contains($0) }),
              (0...uids.count).contains(destination) else {
            return nil
        }

        let moved = source.map { uids[$0] }
        var reordered = uids.enumerated()
            .filter { !source.contains($0.offset) }
            .map(\.element)
        let insertionOffset = destination - source.filter { $0 < destination }.count
        reordered.insert(contentsOf: moved, at: min(insertionOffset, reordered.count))
        return reordered.compactMap { $0 }
    }

    /// Rebuilds a saved device order from the devices on screen. A remembered
    /// device that is absent right now stays right after the device it followed
    /// before, so AirPods that are disconnected while the list is rearranged
    /// keep their place instead of dropping to the end when they reconnect.
    static func mergedDeviceOrder(_ displayed: [String], previous: [String]) -> [String] {
        var merged = displayed
        var placed = Set(displayed)
        var anchor: String?
        for uid in previous {
            if placed.insert(uid).inserted {
                let index = anchor.flatMap { merged.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
                merged.insert(uid, at: index)
            }
            anchor = uid
        }
        return merged
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
            BluetoothDeviceIdentity.preferenceKey($0.id)
        }
    }

    /// Hides or reveals a single device in the status-panel list, by its
    /// normalized address. Manual hides are independent of the automatic
    /// "hide devices not in System Settings" filter, so a device the user hides
    /// stays hidden whatever the profiler reports next.
    func setBluetoothDeviceHidden(_ address: String, hidden: Bool) {
        let key = BluetoothDeviceIdentity.preferenceKey(address)
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
        let key = BluetoothDeviceIdentity.preferenceKey(address)
        guard !key.isEmpty else { return }
        if revealed {
            revealedGhostBluetoothDeviceAddresses.insert(key)
        } else {
            revealedGhostBluetoothDeviceAddresses.remove(key)
        }
    }

    func setNearbyBLEDeviceSelected(_ candidate: NearbyBLEDeviceCandidate, selected: Bool) {
        let rowID = BluetoothDeviceIdentity.bleRowID(candidate.id)
        if selected {
            if let index = nearbyBLESelections.firstIndex(where: { $0.id == candidate.id }) {
                nearbyBLESelections[index].name = candidate.name
                nearbyBLESelections[index].vendor = candidate.vendor
            } else {
                nearbyBLESelections.append(NearbyBLEDeviceSelection(
                    id: candidate.id,
                    name: candidate.name,
                    vendor: candidate.vendor,
                    model: nil
                ))
            }
            if !bluetoothDeviceOrder.contains(rowID) {
                bluetoothDeviceOrder.append(rowID)
            }
            hiddenBluetoothDeviceAddresses.remove(rowID)
            revealedGhostBluetoothDeviceAddresses.remove(rowID)
        } else {
            nearbyBLESelections.removeAll { $0.id == candidate.id }
            bluetoothDeviceOrder.removeAll { BluetoothDeviceIdentity.preferenceKey($0) == rowID }
            hiddenBluetoothDeviceAddresses.remove(rowID)
            revealedGhostBluetoothDeviceAddresses.remove(rowID)
        }
    }

    /// A valid battery response is the only event that creates or refreshes a
    /// persisted nearby row. Row hide/order preferences remain keyed by UUID.
    func updateNearbyBLEMetadata(_ devices: [NearbyBluetoothBatteryDevice]) {
        var updated = nearbyBLESelections
        var changed = false
        for device in devices where (0...100).contains(device.batteryLevel) {
            guard !device.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let index = updated.firstIndex(where: { $0.id == device.id }) {
                updated[index].name = device.name
                updated[index].vendor = .apple
                if let model = device.model { updated[index].model = model }
                updated[index].batteryLevel = device.batteryLevel
                updated[index].batteryLastUpdated = device.lastUpdated
            } else {
                updated.append(NearbyBLEDeviceSelection(
                    id: device.id,
                    name: device.name,
                    vendor: .apple,
                    model: device.model,
                    batteryLevel: device.batteryLevel,
                    batteryLastUpdated: device.lastUpdated
                ))
                let rowID = BluetoothDeviceIdentity.bleRowID(device.id)
                if !bluetoothDeviceOrder.contains(rowID) { bluetoothDeviceOrder.append(rowID) }
            }
            changed = true
        }
        guard changed, updated != nearbyBLESelections else { return }
        nearbyBLESelections = updated
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

    /// Re-reads the macOS charge limit into the full-ring level.
    ///
    /// Called on launch and whenever the follow toggle is switched on. A limit
    /// the plist does not carry, or a plist that no longer parses, leaves the
    /// level exactly where it was: the setting follows the system when it can
    /// and silently stays manual when it cannot, rather than resetting the
    /// user's level on a read failure.
    ///
    /// - Parameter url: The plist to read. Injectable so tests can record one
    ///   instead of depending on what this Mac happens to be set to.
    func applySystemChargeLimit(from url: URL? = nil) {
        // The test seam wins when it is set, so a test never reads whatever
        // limit the machine running it happens to be set to.
        let url = url ?? chargeLimitURLForTesting
        let limit = url.map { SystemChargeLimitReader.chargeLimit(from: $0) }
            ?? SystemChargeLimitReader.chargeLimit()
        guard let limit else { return }
        batteryFullThreshold = Double(limit)
    }

    /// Fills the restore-limit slider in from the system. Like
    /// `applySystemChargeLimit`, this is a one-shot convenience: nothing
    /// re-reads the plist behind the user's back afterwards.
    func applySystemChargeToFullRestoreLimit(from url: URL? = nil) {
        let url = url ?? chargeLimitURLForTesting
        let limit = url.map { SystemChargeLimitReader.chargeLimit(from: $0) }
            ?? SystemChargeLimitReader.chargeLimit()
        guard let limit, (80..<100).contains(limit) else { return }
        chargeToFullRestoreLimit = Double(limit)
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
            fullThreshold: Int(batteryFullThreshold.rounded()),
            textScale: batterySymbolScale * BatteryIconOptions.defaultTextScale,
            ringStrokeScale: ringStrokeStyle.scale,
            batteryStatusColors: batteryStatusColors
        )
    }

    var connectionIconOptions: ConnectionIconOptions {
        ConnectionIconOptions(
            showsWiFiIconForEthernet: showsWiFiIconForEthernet,
            showsWiFiIconForHotspot: showsWiFiIconForHotspot,
            showsWiFiIconForTemporaryConnection: showsWiFiIconForTemporaryConnection,
            showsWiFiIconForInternetSharing: showsWiFiIconForInternetSharing,
            centerSource: connectionCenterSource,
            prioritizesNetworkErrorsOverInputSource: prioritizesNetworkErrorsOverInputSource,
            wifiScale: wifiSymbolScale
        )
    }

    var bluetoothAudioIconOptions: BluetoothAudioIconOptions {
        BluetoothAudioIconOptions(
            replacesNetworkIcon: replacesNetworkIconWithBluetoothAudio,
            usesVolumeColor: usesBluetoothAudioVolumeColor,
            prioritizesNetworkErrors: prioritizesNetworkErrorsOverBluetoothAudio,
            symbolScale: bluetoothSymbolScale,
            networkIconSymbolOverride: bluetoothNetworkIconSymbolName,
            iconChoice: bluetoothAudioIconChoice
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

    func updateTrustedAppleDeviceMetadata(_ candidates: [AppleDeviceCandidate]) {
        var values = Dictionary(
            trustedAppleDeviceMetadata.filter(\.isVerifiedTrustedAppleDevice).map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        for candidate in candidates where candidate.isVerifiedTrustedAppleDevice {
            guard let existing = values[candidate.id] else {
                values[candidate.id] = candidate
                continue
            }
            let transports = ([MobileBatteryTransport.usb, .network] as [MobileBatteryTransport]).filter {
                existing.transports.contains($0) || candidate.transports.contains($0)
            }
            values[candidate.id] = AppleDeviceCandidate(
                id: candidate.id,
                name: candidate.name,
                model: candidate.model ?? existing.model,
                transports: transports,
                trustRequired: false,
                evidence: candidate.evidence
            )
        }
        let updated = values.values.sorted { $0.id.rowID < $1.id.rowID }
        guard updated != trustedAppleDeviceMetadata else { return }
        trustedAppleDeviceMetadata = updated
    }

    init(
        defaults: UserDefaults = .standard,
        systemChargeLimit: () -> Int? = { SystemChargeLimitReader.chargeLimit() }
    ) {
        self.defaults = defaults
        self.statusPanelShortcut = defaults
            .data(forKey: Self.statusPanelShortcutDefaultsKey)
            .flatMap { try? JSONDecoder().decode(StatusPanelShortcut.self, from: $0) }
        let appleMigration = AppleDeviceSettingsMigration.migrate(defaults: defaults)
        let hadLegacyInstallMarker =
            defaults.bool(forKey: Self.sparkleHasLaunchedBeforeDefaultsKey)
            || defaults.bool(forKey: Self.hasSeenIconGuideDefaultsKey)
            || defaults.bool(forKey: Self.hasCompletedIconGuideOnboardingDefaultsKey)
        if let storedConsentVersion = defaults.object(
            forKey: Self.telemetryConsentVersionDefaultsKey
        ) as? Int {
            self.telemetryConsentVersion = storedConsentVersion
            self.sharesAnonymousAnalytics = defaults.bool(
                forKey: Self.sharesAnonymousAnalyticsDefaultsKey
            )
        } else if hadLegacyInstallMarker {
            self.telemetryConsentVersion = TelemetryConsent.currentVersion
            self.sharesAnonymousAnalytics = false
            defaults.set(false, forKey: Self.sharesAnonymousAnalyticsDefaultsKey)
            defaults.set(
                TelemetryConsent.currentVersion,
                forKey: Self.telemetryConsentVersionDefaultsKey
            )
        } else {
            self.telemetryConsentVersion = 0
            self.sharesAnonymousAnalytics = false
            defaults.set(false, forKey: Self.sharesAnonymousAnalyticsDefaultsKey)
            defaults.set(0, forKey: Self.telemetryConsentVersionDefaultsKey)
        }
        let storedTrustedMetadata = Self.decodedTrustedAppleDeviceMetadata(
            defaults.data(forKey: Self.trustedAppleDeviceMetadataDefaultsKey)
        )
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
        let storedFullThreshold = (defaults.object(forKey: Self.batteryFullThresholdDefaultsKey) as? NSNumber)?.doubleValue
        let storedRestoreLimit = (defaults.object(
            forKey: Self.chargeToFullRestoreLimitDefaultsKey
        ) as? NSNumber)?.doubleValue
        let storedBatterySymbolScale = (defaults.object(forKey: Self.batterySymbolScaleDefaultsKey) as? NSNumber)?.doubleValue
        let storedOutputDeviceLimit = (defaults.object(forKey: Self.maxVisibleOutputDevicesDefaultsKey) as? NSNumber)?.intValue
        let storedInputDeviceLimit = (defaults.object(forKey: Self.maxVisibleInputDevicesDefaultsKey) as? NSNumber)?.intValue
        let storedBluetoothDeviceLimit = (defaults.object(
            forKey: Self.maxVisibleBluetoothDevicesDefaultsKey
        ) as? NSNumber)?.intValue
        let storedBluetoothDeviceOrder = defaults.stringArray(
            forKey: Self.bluetoothDeviceOrderDefaultsKey
        ) ?? []
        let storedNearbyBLESelections = Self.decodedNearbyBLESelections(
            defaults.data(forKey: Self.nearbyBLEConsentDefaultsKey)
        )
        let storedHidesGhostBluetoothDevices = defaults.object(
            forKey: Self.hidesGhostBluetoothDevicesDefaultsKey
        ) as? Bool ?? true
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
        let storedHiddenOutputDeviceUIDs = Set(
            defaults.stringArray(forKey: Self.hiddenOutputDeviceUIDsDefaultsKey) ?? []
        )
        let storedInputDeviceOrder = defaults.stringArray(forKey: Self.inputDeviceOrderDefaultsKey) ?? []
        let storedHiddenInputDeviceUIDs = Set(
            defaults.stringArray(forKey: Self.hiddenInputDeviceUIDsDefaultsKey) ?? []
        )
        let storedExternalVolumeConfigurations = Self.decodedExternalVolumeConfigurations(
            defaults.data(forKey: Self.externalVolumeConfigurationsDefaultsKey)
        )
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
        self.showsBatteryPowerFlow = defaults.object(forKey: Self.showsBatteryPowerFlowDefaultsKey) as? Bool ?? true
        self.showsBatteryPowerInfoBar = defaults.object(forKey: Self.showsBatteryPowerInfoBarDefaultsKey) as? Bool ?? false
        self.showsHighEnergyApps = defaults.object(forKey: Self.showsHighEnergyAppsDefaultsKey) as? Bool ?? false
        self.highEnergyAppsRefreshIntervalSeconds = Self.clampedHighEnergyAppsRefreshInterval(
            defaults.object(forKey: Self.highEnergyAppsRefreshIntervalDefaultsKey) as? Double
                ?? Self.defaultHighEnergyAppsRefreshIntervalSeconds
        )
        self.showsChargeToFullNowButton = defaults.object(
            forKey: Self.showsChargeToFullNowButtonDefaultsKey
        ) as? Bool ?? true
        self.showsChargingIndicator = defaults.object(forKey: Self.showsChargingIndicatorDefaultsKey) as? Bool ?? true
        let legacyChargingEffect = defaults.object(
            forKey: Self.showsChargingEffectDefaultsKey
        ) as? Bool
        let storedMenuBarChargingEffect = defaults.object(
            forKey: Self.showsMenuBarChargingEffectDefaultsKey
        ) as? Bool
        let storedDockChargingEffect = defaults.object(
            forKey: Self.showsDockChargingEffectDefaultsKey
        ) as? Bool
        let resolvedMenuBarChargingEffect =
            storedMenuBarChargingEffect ?? legacyChargingEffect ?? true
        let resolvedDockChargingEffect =
            storedDockChargingEffect ?? legacyChargingEffect ?? true
        self.showsMenuBarChargingEffect = resolvedMenuBarChargingEffect
        self.showsDockChargingEffect = resolvedDockChargingEffect
        if storedMenuBarChargingEffect == nil {
            defaults.set(
                resolvedMenuBarChargingEffect,
                forKey: Self.showsMenuBarChargingEffectDefaultsKey
            )
        }
        if storedDockChargingEffect == nil {
            defaults.set(
                resolvedDockChargingEffect,
                forKey: Self.showsDockChargingEffectDefaultsKey
            )
        }
        self.showsChargingBoltHeartbeat = defaults.object(
            forKey: Self.showsChargingBoltHeartbeatDefaultsKey
        ) as? Bool ?? true
        self.showsPercentageWhenConnected = defaults.object(
            forKey: Self.showsPercentageWhenConnectedDefaultsKey
        ) as? Bool ?? false
        self.usesBatteryStatusColors = defaults.object(forKey: Self.usesBatteryStatusColorsDefaultsKey) as? Bool ?? true
        self.batteryStatusColors = BatteryStatusColors(
            charging: BatteryStatusColorSelection(
                storageValue: defaults.string(forKey: Self.batteryStatusColorsChargingDefaultsKey) ?? "system"
            ),
            lowPower: BatteryStatusColorSelection(
                storageValue: defaults.string(forKey: Self.batteryStatusColorsLowPowerDefaultsKey) ?? "system"
            ),
            critical: BatteryStatusColorSelection(
                storageValue: defaults.string(forKey: Self.batteryStatusColorsCriticalDefaultsKey) ?? "system"
            )
        )
        self.batterySymbolScale = Self.clampedBatterySymbolScale(
            storedBatterySymbolScale ?? Self.defaultBatterySymbolScale
        )
        self.batteryCriticalThreshold = Self.clampedBatteryCriticalThreshold(
            storedCriticalThreshold ?? Self.defaultBatteryCriticalThreshold
        )
        self.batteryFullThreshold = Self.clampedBatteryFullThreshold(
            storedFullThreshold ?? Self.defaultBatteryFullThreshold
        )
        self.chargeToFullRestoreLimit = Self.clampedChargeToFullRestoreLimit(
            storedRestoreLimit
                ?? Self.systemChargeToFullRestoreLimit(read: systemChargeLimit)
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
        self.showsLocalIPAddress = defaults.object(
            forKey: Self.showsLocalIPAddressDefaultsKey
        ) as? Bool ?? false
        // One-time migration: the centre slot used to be a network-source
        // choice plus a separate "battery percentage in the connection slot"
        // switch, and the switch won at draw time. Preserve that effective
        // choice, then drop the legacy key so a later manual change survives.
        let legacyPercentageInSlot = defaults.object(
            forKey: Self.showsBatteryPercentageInConnectionSlotDefaultsKey
        ) as? Bool ?? false
        let storedCenterSource = defaults.string(
            forKey: Self.connectionCenterSourceDefaultsKey
        )
        .flatMap(ConnectionCenterSource.init(rawValue:))
        self.connectionCenterSource = legacyPercentageInSlot
            ? .batteryPercentage
            : (storedCenterSource ?? .automatic)
        if legacyPercentageInSlot {
            defaults.removeObject(forKey: Self.showsBatteryPercentageInConnectionSlotDefaultsKey)
        }
        self.prioritizesNetworkErrorsOverInputSource = defaults.object(
            forKey: Self.prioritizesNetworkErrorsOverInputSourceDefaultsKey
        ) as? Bool ?? true
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
        self.showsBluetoothPowerControl = defaults.object(
            forKey: Self.showsBluetoothPowerControlDefaultsKey
        ) as? Bool ?? true
        self.controlsLowPowerMode = defaults.object(
            forKey: Self.controlsLowPowerModeDefaultsKey
        ) as? Bool ?? false
        self.showsNearbyBluetoothBatteryDevices = defaults.object(
            forKey: Self.showsNearbyBluetoothBatteryDevicesDefaultsKey
        ) as? Bool ?? false
        self.showsMobileDeviceBatteryLevels = defaults.object(
            forKey: Self.showsMobileDeviceBatteryLevelsDefaultsKey
        ) as? Bool ?? false
        self.showsAppleDevicesAndBattery = appleMigration.isEnabled
        self.refreshesAppleBatteriesInBackground = defaults.object(
            forKey: Self.refreshesAppleBatteriesInBackgroundDefaultsKey
        ) as? Bool ?? false
        self.appleBatteryRefreshIntervalMinutes = Self.clampedAppleBatteryRefreshInterval(
            (defaults.object(forKey: Self.appleBatteryRefreshIntervalMinutesDefaultsKey) as? NSNumber)?.intValue
                ?? Self.defaultAppleBatteryRefreshIntervalMinutes
        )
        self.archivedLegacyNearbyBLESelections = appleMigration.archivedLegacyBLESelections
        self.trustedAppleDeviceMetadata = storedTrustedMetadata
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
        self.maxVisibleInputDevices = Self.clampedInputDeviceLimit(
            storedInputDeviceLimit ?? Self.defaultMaxVisibleInputDevices
        )
        self.alwaysShowsAllInputDevices = defaults.object(
            forKey: Self.alwaysShowsAllInputDevicesDefaultsKey
        ) as? Bool ?? false
        self.showsBluetoothDeviceList = defaults.object(
            forKey: Self.showsBluetoothDeviceListDefaultsKey
        ) as? Bool ?? true
        self.maxVisibleBluetoothDevices = Self.clampedBluetoothDeviceLimit(
            storedBluetoothDeviceLimit ?? Self.defaultMaxVisibleBluetoothDevices
        )
        self.bluetoothDeviceOrder = storedBluetoothDeviceOrder
        self.nearbyBLESelections = storedNearbyBLESelections
        self.hidesGhostBluetoothDevices = storedHidesGhostBluetoothDevices
        self.hiddenBluetoothDeviceAddresses = storedHiddenBluetoothDeviceAddresses
        self.revealedGhostBluetoothDeviceAddresses = storedRevealedGhostBluetoothDeviceAddresses
        self.bluetoothNetworkIconDeviceAddress = defaults.string(
            forKey: Self.bluetoothNetworkIconDeviceAddressDefaultsKey
        )
        self.bluetoothNetworkIconSymbolName = defaults.string(
            forKey: Self.bluetoothNetworkIconSymbolNameDefaultsKey
        )
        self.bluetoothAudioIconChoiceRawValue = defaults.string(
            forKey: Self.bluetoothAudioIconChoiceDefaultsKey
        ) ?? BluetoothAudioIconChoice.automatic.rawValue
        self.alwaysShowsAllOutputDevices = defaults.object(
            forKey: Self.alwaysShowsAllOutputDevicesDefaultsKey
        ) as? Bool ?? false
        self.outputDeviceOrder = storedOutputDeviceOrder
        self.hiddenOutputDeviceUIDs = storedHiddenOutputDeviceUIDs
        self.inputDeviceOrder = storedInputDeviceOrder
        self.hiddenInputDeviceUIDs = storedHiddenInputDeviceUIDs
        self.externalVolumeConfigurations = storedExternalVolumeConfigurations
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

    private static func decodedNearbyBLESelections(_ data: Data?) -> [NearbyBLEDeviceSelection] {
        guard let data,
              let decoded = try? JSONDecoder().decode([NearbyBLEDeviceSelection].self, from: data) else {
            return []
        }
        var seen: Set<UUID> = []
        return decoded.filter { seen.insert($0.id).inserted }
    }

    private static func decodedExternalVolumeConfigurations(
        _ data: Data?
    ) -> [String: ExternalVolumeConfiguration] {
        guard let data,
              let decoded = try? JSONDecoder().decode(
                  [String: ExternalVolumeConfiguration].self,
                  from: data
              )
        else {
            return [:]
        }

        var sanitized: [String: ExternalVolumeConfiguration] = [:]
        for (rawUID, configuration) in decoded {
            let uid = rawUID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !uid.isEmpty,
                  let configuration = configuration.sanitized(),
                  configuration != .default
            else {
                continue
            }
            sanitized[uid] = configuration
        }
        return sanitized
    }

    private static func decodedTrustedAppleDeviceMetadata(_ data: Data?) -> [AppleDeviceCandidate] {
        guard let data,
              let decoded = try? JSONDecoder().decode([AppleDeviceCandidate].self, from: data) else {
            return []
        }
        var byID: [AppleDeviceID: AppleDeviceCandidate] = [:]
        for candidate in decoded where candidate.isVerifiedTrustedAppleDevice {
            byID[candidate.id] = candidate
        }
        return byID.values.sorted { $0.id.rowID < $1.id.rowID }
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

    static func clampedBatteryFullThreshold(_ value: Double) -> Double {
        guard value.isFinite else { return defaultBatteryFullThreshold }
        return min(
            batteryFullThresholdRange.upperBound,
            max(batteryFullThresholdRange.lowerBound, value)
        ).rounded()
    }

    static func clampedChargeToFullRestoreLimit(_ value: Double) -> Double {
        guard value.isFinite else { return defaultChargeToFullRestoreLimit }
        let clamped = min(
            chargeToFullRestoreLimitRange.upperBound,
            max(chargeToFullRestoreLimitRange.lowerBound, value)
        )
        // PowerUI only accepts the standard five-percent steps.
        return (clamped / 5).rounded() * 5
    }

    /// The first-run default: the limit macOS currently enforces, or "no
    /// limit" (100%) when the system has no readable user limit.
    static func systemChargeToFullRestoreLimit(
        read: () -> Int? = { SystemChargeLimitReader.chargeLimit() }
    ) -> Double {
        guard let limit = read(), (80..<100).contains(limit) else {
            return defaultChargeToFullRestoreLimit
        }
        return Double(limit)
    }

    static func clampedRefreshInterval(_ value: Double) -> Double {
        guard value.isFinite else { return defaultRefreshIntervalSeconds }
        let clamped = min(refreshIntervalRange.upperBound, max(refreshIntervalRange.lowerBound, value))
        return (clamped / 5).rounded() * 5
    }

    static func clampedHighEnergyAppsRefreshInterval(_ value: Double) -> Double {
        guard value.isFinite else { return defaultHighEnergyAppsRefreshIntervalSeconds }
        let clamped = min(
            highEnergyAppsRefreshIntervalRange.upperBound,
            max(highEnergyAppsRefreshIntervalRange.lowerBound, value)
        )
        return (clamped / 5).rounded() * 5
    }

    static func clampedAppleBatteryRefreshInterval(_ value: Int) -> Int {
        min(
            Self.appleBatteryRefreshIntervalMinutesRange.upperBound,
            max(Self.appleBatteryRefreshIntervalMinutesRange.lowerBound, value)
        )
    }

    static func clampedOutputDeviceLimit(_ value: Int) -> Int {
        min(outputDeviceLimitRange.upperBound, max(outputDeviceLimitRange.lowerBound, value))
    }

    static func clampedInputDeviceLimit(_ value: Int) -> Int {
        min(inputDeviceLimitRange.upperBound, max(inputDeviceLimitRange.lowerBound, value))
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
