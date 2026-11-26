import Foundation

/// Bridges the core `SettingsStore` into the semantic `SettingsStateProvider`.
///
/// Reads and writes go through the store's real `@Published` properties (and
/// domain methods such as `setEnabledHardwareRingSlots`), so persistence,
/// side effects and the menu-bar/Dock/live-update path stay on the normal code
/// path. Only settings whose `provider == "core"` are handled; other domains
/// (Localization, LaunchAtLogin, ...) return `nil` and ignore writes.
@MainActor
final class CoreSettingsProvider: SettingsStateProvider {
    private let store: SettingsStore

    /// Ids this provider can read and write. Kept in one place so a
    /// regression test can assert every writable core descriptor is handled.
    static let handledPreferenceIDs: Set<String> = [
        "audio.input.maxVisibleDevices",
        "audio.input.showAllDevices",
        "audio.output.maxVisibleDevices",
        "audio.output.showAllDevices",
        "audio.popup.naturalScrolling",
        "audio.popup.scrollAdjustsVolume",
        "audio.spatialControls.enabled",
        "audio.volumeDisplayStyle",
        "battery.appleBattery.refreshIntervalMinutes",
        "battery.appleDevicesAndBattery.enabled",
        "battery.automation.autoLowPower",
        "battery.automation.controlsLowPowerMode",
        "battery.automation.lowPowerThreshold",
        "battery.bluetoothPowerControl.enabled",
        "battery.bottomIndicatorStyle",
        "battery.chargeToFullButton.enabled",
        "battery.chargeToFullRestoreLimit",
        "battery.charging.boltHeartbeat",
        "battery.charging.dockEffect",
        "battery.charging.menuBarEffect",
        "battery.confirmWiFiPowerOff",
        "battery.highEnergyApps.enabled",
        "battery.highEnergyApps.refreshIntervalSeconds",
        "battery.marker.charging",
        "battery.marker.connected",
        "battery.marker.noBattery",
        "battery.marker.onBattery",
        "battery.powerFlow.enabled",
        "battery.powerInfoBar.enabled",
        "battery.refreshInterval.onBattery",
        "battery.refreshInterval.onPower",
        "battery.simulateNoBattery",
        "battery.splitGapProgress",
        "battery.statusColors.enabled",
        "battery.symbolScale",
        "battery.thresholds.critical",
        "battery.thresholds.full",
        "battery.wifiPowerControl.enabled",
        "bluetooth.appleBattery.backgroundRefresh",
        "bluetooth.batteryLevels.enabled",
        "bluetooth.conversationAwarenessControls.enabled",
        "bluetooth.deviceList.enabled",
        "bluetooth.devices.hidden",
        "bluetooth.listeningMode.enabled",
        "bluetooth.listeningMode.previewDeviceCount",
        "bluetooth.listeningMode.previewDeviceName",
        "bluetooth.listeningMode.previewEnabled",
        "bluetooth.listeningMode.previewLanguage",
        "bluetooth.maxVisibleDevices",
        "brightness.betterDisplay.combined",
        "brightness.sliderMatchesBrightnessThickness",
        "general.iconSize",
        "general.menuBarRightClickAction",
        "hardware.history.backgroundEnabled",
        "hardware.history.windowMinutes",
        "hardware.metricBottomIndicatorStyle",
        "hardware.network.downloadCapMbps",
        "hardware.network.uploadCapMbps",
        "hardware.refresh.cpuUsage",
        "hardware.refresh.disk",
        "hardware.refresh.gpuUsage",
        "hardware.refresh.memory",
        "hardware.refresh.network",
        "hardware.refresh.temperature",
        "hardware.ring.memoryDisplayMode",
        "hardware.ring.ssdDisplayMode",
        "hardware.rings.enabled",
        "hardware.ssd.externalVolumePaths",
        "hardware.ssd.includeExternalInPercent",
        "hardware.summary.enabled",
        "hardware.summaryMetrics",
        "hardware.temperature.enabled",
        "hardware.topApps.enabled",
        "hardware.topApps.refreshSeconds",
        "icon.airPods.ringUsesDualRing",
        "icon.airPods.topSymbolInRing",
        "icon.airPodsRingFallback",
        "icon.appIconPlacement",
        "icon.center.source",
        "icon.cpuRingCenterContent",
        "icon.dockIconBackground",
        "icon.footer.metric",
        "icon.footer.source",
        "icon.gpuRingCenterContent",
        "icon.inputSourceMarkerStyle",
        "icon.localPluginDirectories",
        "icon.network.wifiIconForEthernet",
        "icon.network.wifiIconForHotspot",
        "icon.network.wifiIconForInternetSharing",
        "icon.network.wifiIconForTemporaryConnection",
        "icon.outerRing.hardware.layout",
        "icon.outerRing.hardware.primaryMetric",
        "icon.outerRing.hardware.ringSlots",
        "icon.outerRing.hardware.secondaryMetric",
        "icon.outerRing.hardware.splitGapProgress",
        "icon.outerRing.source",
        "icon.ring.monochromeCharging",
        "icon.ringStrokeStyle",
        "keepAwake.allowLidSleepOnBattery",
        "keepAwake.autoDisableOnLowBattery",
        "keepAwake.displayControl",
        "keepAwake.lidControl",
        "network.chart.fixedScale",
        "network.prioritizeErrors",
        "network.showLocalIPAddress",
        "network.symbolScale",
        "network.wifiBottomIndicatorStyle",
        "panel.appearance.backgroundStyle",
        "panel.appearance.boldText",
        "panel.appearance.boldText.mediumWeight",
        "panel.appearance.boldText.titleWeight",
        "panel.behavior.detailsAlongside",
        "panel.behavior.keepOpenWhenOpeningSettings",
        "panel.behavior.scrollWheelStepPercent",
        "panel.behavior.showOnHover",
        "panel.modules.enabled",
        "panel.modules.hardwareMonitor"
    ]


    init(store: SettingsStore) {
        self.store = store
    }

    // MARK: - Read

    func value(for id: String) -> SettingsTransferValue? {
        switch id {
        case "general.menuBarRightClickAction":
            return .string(store.menuBarRightClickAction.rawValue)
        case "general.iconSize":
            return .number(store.iconSize)
        case "panel.appearance.backgroundStyle":
            return .string(store.panelBackgroundStyle.rawValue)
        case "panel.appearance.boldText":
            return .bool(store.statusPanelBoldTextEnabled)
        case "panel.appearance.boldText.titleWeight":
            return .bool(store.statusPanelBoldTextEnabled)
        case "panel.appearance.boldText.mediumWeight":
            return .bool(store.statusPanelMediumTextEnabled)
        case "panel.behavior.showOnHover":
            return .bool(store.showsPanelOnHover)
        case "panel.behavior.keepOpenWhenOpeningSettings":
            return .bool(store.keepsPanelOpenWhenOpeningSettings)
        case "icon.outerRing.source":
            return .string(store.outerRingContent.rawValue)
        case "icon.outerRing.hardware.layout":
            return .string(store.hardwareRingConfiguration.layout.rawValue)
        case "icon.outerRing.hardware.primaryMetric":
            return .string(store.hardwareRingConfiguration.primaryMetric.rawValue)
        case "icon.outerRing.hardware.secondaryMetric":
            return store.hardwareRingConfiguration.secondaryMetric.map { .string($0.rawValue) }
        case "icon.outerRing.hardware.ringSlots":
            let values = store.enabledHardwareRingSlots.map(\.rawValue).sorted().map { SettingsTransferValue.string($0) }
            return .array(values)
        case "icon.center.source":
            return .string(store.connectionCenterSource.rawValue)
        case "icon.footer.source":
            return .string(store.bottomIndicatorSource.rawValue)
        case "icon.footer.metric":
            return .string(store.bottomIndicatorMetric.rawValue)
        case "hardware.rings.enabled":
            return .bool(store.showsHardwareRings)
        case "hardware.summary.enabled":
            return .bool(store.showsHardwareSummaryRow)
        case "hardware.topApps.enabled":
            return .bool(store.showsHardwareTopApps)
        case "hardware.temperature.enabled":
            return .bool(store.hardwareTemperatureMonitoringEnabled)
        case "hardware.history.backgroundEnabled":
            return .bool(store.hardwareBackgroundHistoryEnabled)
        case "hardware.refresh.cpuUsage":
            return .number(Double(store.hardwareCPUUsageRefreshSeconds))
        case "hardware.refresh.gpuUsage":
            return .number(Double(store.hardwareGPUUsageRefreshSeconds))
        case "hardware.refresh.memory":
            return .number(Double(store.hardwareMemoryRefreshSeconds))
        case "hardware.refresh.network":
            return .number(Double(store.hardwareNetworkRefreshSeconds))
        case "hardware.refresh.temperature":
            return .number(Double(store.hardwareTemperatureRefreshSeconds))
        case "hardware.refresh.disk":
            return .number(Double(store.hardwareDiskRefreshSeconds))
        case "hardware.topApps.refreshSeconds":
            return .number(Double(store.hardwareTopAppsRefreshSeconds))
        case "hardware.history.windowMinutes":
            return .number(Double(store.hardwareHistoryWindowMinutes))
        case "hardware.network.downloadCapMbps":
            return .number(store.hardwareDownloadCapMbps)
        case "hardware.network.uploadCapMbps":
            return .number(store.hardwareUploadCapMbps)
        case "battery.thresholds.critical":
            return .number(store.batteryCriticalThreshold)
        case "battery.thresholds.full":
            return .number(store.batteryFullThreshold)
        case "battery.automation.autoLowPower":
            return .bool(store.autoEnablesLowPowerMode)
        case "battery.automation.lowPowerThreshold":
            return .number(store.autoLowPowerThreshold)
        case "battery.powerFlow.enabled":
            return .bool(store.showsBatteryPowerFlow)
        case "battery.powerInfoBar.enabled":
            return .bool(store.showsBatteryPowerInfoBar)
        case "battery.highEnergyApps.enabled":
            return .bool(store.showsHighEnergyApps)
        case "keepAwake.displayControl":
            return .bool(store.showsKeepScreenButton)
        case "keepAwake.lidControl":
            return .bool(store.showsLidSleepButton)
        case "keepAwake.allowLidSleepOnBattery":
            return .bool(store.allowLidSleepOnBattery)
        case "keepAwake.autoDisableOnLowBattery":
            return .bool(store.autoDisableLidSleepOnLowBattery)
        case "bluetooth.deviceList.enabled":
            return .bool(store.showsBluetoothDeviceList)
        case "bluetooth.batteryLevels.enabled":
            return .bool(store.showsBluetoothBatteryLevels)
        case "bluetooth.appleBattery.backgroundRefresh":
            return .bool(store.refreshesAppleBatteriesInBackground)
        case "bluetooth.devices.hidden":
            return .array(store.hiddenBluetoothDeviceAddresses.sorted().map { .string($0) })
        case "audio.output.maxVisibleDevices":
            return .number(Double(store.maxVisibleOutputDevices))
        case "audio.output.showAllDevices":
            return .bool(store.alwaysShowsAllOutputDevices)
        case "audio.input.maxVisibleDevices":
            return .number(Double(store.maxVisibleInputDevices))
        case "audio.input.showAllDevices":
            return .bool(store.alwaysShowsAllInputDevices)
        case "brightness.betterDisplay.combined":
            return .bool(store.useBetterDisplayCombinedBrightness)
        case "icon.appIconPlacement":
            return .string(store.appIconPlacement.rawValue)
        case "icon.dockIconBackground":
            return .string(store.dockIconBackgroundPreference.rawValue)
        case "icon.airPodsRingFallback":
            return .string(store.airPodsRingFallback.rawValue)
        case "icon.cpuRingCenterContent":
            return .string(store.cpuRingCenterContent.rawValue)
        case "icon.gpuRingCenterContent":
            return .string(store.gpuRingCenterContent.rawValue)
        case "icon.ringStrokeStyle":
            return .string(store.ringStrokeStyle.rawValue)
        case "icon.inputSourceMarkerStyle":
            return .string(store.inputSourceMarkerStyle.rawValue)
        case "audio.volumeDisplayStyle":
            return .string(store.volumeDisplayStyle.rawValue)
        case "battery.bottomIndicatorStyle":
            return .string(store.batteryBottomIndicatorStyle.rawValue)
        case "hardware.metricBottomIndicatorStyle":
            return .string(store.metricBottomIndicatorStyle.rawValue)
        case "network.wifiBottomIndicatorStyle":
            return .string(store.wifiBottomIndicatorStyle.rawValue)
        case "hardware.ring.memoryDisplayMode":
            return .string(store.memoryRingDisplayMode.rawValue)
        case "hardware.ring.ssdDisplayMode":
            return .string(store.ssdRingDisplayMode.rawValue)
        case "icon.localPluginDirectories":
            return .array(store.localIconPluginDirectories.map { .string($0) })
        case "hardware.ssd.externalVolumePaths":
            return .array(store.hardwareSSDExternalVolumePaths.sorted().map { .string($0) })
        case "hardware.summaryMetrics":
            return .array(store.enabledHardwareSummaryMetrics.map(\.rawValue).sorted().map { .string($0) })
        case "panel.modules.hardwareMonitor":
            return .bool(store.enabledPopupSections.contains(.hardwareMonitor))
        case "audio.popup.naturalScrolling":
            return .bool(store.popupVolumeNaturalScrolling)
        case "audio.popup.scrollAdjustsVolume":
            return .bool(store.popupPanelScrollAdjustsVolume)
        case "audio.spatialControls.enabled":
            return .bool(store.showsSpatialAudioControls)
        case "battery.appleBattery.refreshIntervalMinutes":
            return .number(Double(store.appleBatteryRefreshIntervalMinutes))
        case "battery.appleDevicesAndBattery.enabled":
            return .bool(store.showsAppleDevicesAndBattery)
        case "battery.bluetoothPowerControl.enabled":
            return .bool(store.showsBluetoothPowerControl)
        case "battery.chargeToFullButton.enabled":
            return .bool(store.showsChargeToFullNowButton)
        case "battery.chargeToFullRestoreLimit":
            return .number(store.chargeToFullRestoreLimit)
        case "battery.charging.boltHeartbeat":
            return .bool(store.showsChargingBoltHeartbeat)
        case "battery.charging.dockEffect":
            return .bool(store.showsDockChargingEffect)
        case "battery.charging.menuBarEffect":
            return .bool(store.showsMenuBarChargingEffect)
        case "battery.confirmWiFiPowerOff":
            return .bool(store.confirmsWiFiPowerOff)
        case "battery.highEnergyApps.refreshIntervalSeconds":
            return .number(store.highEnergyAppsRefreshIntervalSeconds)
        case "battery.marker.charging":
            return .string(store.batteryChargingMarker.rawValue)
        case "battery.marker.connected":
            return .string(store.batteryConnectedMarker.rawValue)
        case "battery.marker.noBattery":
            return .string(store.batteryNoBatteryMarker.rawValue)
        case "battery.marker.onBattery":
            return .string(store.batteryOnBatteryMarker.rawValue)
        case "battery.refreshInterval.onBattery":
            return .number(store.refreshIntervalOnBatterySeconds)
        case "battery.refreshInterval.onPower":
            return .number(store.refreshIntervalOnPowerSeconds)
        case "battery.simulateNoBattery":
            return .bool(store.simulatesNoBattery)
        case "battery.splitGapProgress":
            return .bool(store.batterySplitGapProgress)
        case "battery.statusColors.enabled":
            return .bool(store.usesBatteryStatusColors)
        case "battery.symbolScale":
            return .number(store.batterySymbolScale)
        case "battery.wifiPowerControl.enabled":
            return .bool(store.showsWiFiPowerControl)
        case "battery.automation.controlsLowPowerMode":
            return .bool(store.controlsLowPowerMode)
        case "bluetooth.conversationAwarenessControls.enabled":
            return .bool(store.showsConversationAwarenessControls)
        case "bluetooth.listeningMode.enabled":
            return .bool(store.showsBluetoothListeningMode)
        case "bluetooth.listeningMode.previewDeviceCount":
            return .number(Double(store.bluetoothListeningModePreviewDeviceCount))
        case "bluetooth.listeningMode.previewDeviceName":
            return .string(store.bluetoothListeningModePreviewDeviceName)
        case "bluetooth.listeningMode.previewEnabled":
            return .bool(store.previewsBluetoothListeningMode)
        case "bluetooth.listeningMode.previewLanguage":
            return .string(store.bluetoothListeningModePreviewLanguage)
        case "bluetooth.maxVisibleDevices":
            return .number(Double(store.maxVisibleBluetoothDevices))
        case "brightness.sliderMatchesBrightnessThickness":
            return .bool(store.panelLevelSliderMatchesBrightnessThickness)
        case "hardware.ssd.includeExternalInPercent":
            return .bool(store.hardwareSSDIncludeExternalInPercent)
        case "icon.airPods.ringUsesDualRing":
            return .bool(store.airPodsRingUsesDualRing)
        case "icon.airPods.topSymbolInRing":
            return .bool(store.showsAirPodsTopSymbolInRing)
        case "icon.network.wifiIconForEthernet":
            return .bool(store.showsWiFiIconForEthernet)
        case "icon.network.wifiIconForHotspot":
            return .bool(store.showsWiFiIconForHotspot)
        case "icon.network.wifiIconForInternetSharing":
            return .bool(store.showsWiFiIconForInternetSharing)
        case "icon.network.wifiIconForTemporaryConnection":
            return .bool(store.showsWiFiIconForTemporaryConnection)
        case "icon.outerRing.hardware.splitGapProgress":
            return .bool(store.hardwareRingSplitGapProgress)
        case "icon.ring.monochromeCharging":
            return store.monochromeChargingRing.map { .bool($0) }
        case "network.chart.fixedScale":
            return .bool(store.hardwareNetworkChartFixedScale)
        case "network.prioritizeErrors":
            return .bool(store.prioritizesNetworkErrors)
        case "network.showLocalIPAddress":
            return .bool(store.showsLocalIPAddress)
        case "network.symbolScale":
            return .number(store.wifiSymbolScale)
        case "panel.behavior.detailsAlongside":
            return .bool(store.showsPanelDetailsAlongside)
        case "panel.behavior.scrollWheelStepPercent":
            return .number(store.popupScrollWheelStepPercent)
        case "panel.modules.enabled":
            return .array(store.enabledPopupSections.map(\.rawValue).sorted().map { .string($0) })
        default:
            return nil
        }
    }

    // MARK: - Write

    func setValue(_ value: SettingsTransferValue, for id: String) {
        switch id {
        case "general.menuBarRightClickAction":
            if case .string(let raw) = value, let parsed = MenuBarRightClickAction(rawValue: raw) {
                store.menuBarRightClickAction = parsed
            }
        case "general.iconSize":
            if let number = Self.number(value) { store.iconSize = number }
        case "panel.appearance.backgroundStyle":
            if case .string(let raw) = value, let parsed = PanelBackgroundStyle(rawValue: raw) {
                store.panelBackgroundStyle = parsed
            }
        case "panel.appearance.boldText":
            if case .bool(let flag) = value { store.applyPanelBoldTextToggle(flag) }
        case "panel.appearance.boldText.titleWeight":
            if case .bool(let flag) = value { store.statusPanelBoldTextEnabled = flag }
        case "panel.appearance.boldText.mediumWeight":
            if case .bool(let flag) = value { store.statusPanelMediumTextEnabled = flag }
        case "panel.behavior.showOnHover":
            if case .bool(let flag) = value { store.showsPanelOnHover = flag }
        case "panel.behavior.keepOpenWhenOpeningSettings":
            if case .bool(let flag) = value { store.keepsPanelOpenWhenOpeningSettings = flag }
        case "icon.outerRing.source":
            if case .string(let raw) = value, let parsed = OuterRingContent(rawValue: raw) {
                store.outerRingContent = parsed
            }
        case "icon.outerRing.hardware.layout":
            if case .string(let raw) = value, let parsed = HardwareRingLayout(rawValue: raw) {
                var configuration = store.hardwareRingConfiguration
                configuration.layout = parsed
                if parsed == .single { configuration.secondaryMetric = nil }
                store.hardwareRingConfiguration = configuration
            }
        case "icon.outerRing.hardware.primaryMetric":
            if case .string(let raw) = value, let parsed = HardwareMonitorMetric(rawValue: raw) {
                var configuration = store.hardwareRingConfiguration
                configuration.primaryMetric = parsed
                store.hardwareRingConfiguration = configuration
            }
        case "icon.outerRing.hardware.secondaryMetric":
            if case .string(let raw) = value, let parsed = HardwareMonitorMetric(rawValue: raw) {
                var configuration = store.hardwareRingConfiguration
                configuration.secondaryMetric = parsed
                store.hardwareRingConfiguration = configuration
            }
        case "icon.outerRing.hardware.ringSlots":
            let slots = Set(Self.strings(value).compactMap { HardwareRingSlot(rawValue: $0) })
            store.setEnabledHardwareRingSlots(slots)
        case "icon.center.source":
            if case .string(let raw) = value, let parsed = ConnectionCenterSource(rawValue: raw) {
                store.connectionCenterSource = parsed
            }
        case "icon.footer.source":
            if case .string(let raw) = value, let parsed = BottomIndicatorSource(rawValue: raw) {
                store.bottomIndicatorSource = parsed
            }
        case "icon.footer.metric":
            if case .string(let raw) = value, let parsed = BottomIndicatorMetric(rawValue: raw) {
                store.bottomIndicatorMetric = parsed
            }
        case "hardware.rings.enabled":
            if case .bool(let flag) = value { store.showsHardwareRings = flag }
        case "hardware.summary.enabled":
            if case .bool(let flag) = value { store.showsHardwareSummaryRow = flag }
        case "hardware.topApps.enabled":
            if case .bool(let flag) = value { store.showsHardwareTopApps = flag }
        case "hardware.temperature.enabled":
            if case .bool(let flag) = value { store.hardwareTemperatureMonitoringEnabled = flag }
        case "hardware.history.backgroundEnabled":
            if case .bool(let flag) = value { store.hardwareBackgroundHistoryEnabled = flag }
        case "hardware.refresh.cpuUsage":
            if let number = Self.number(value) { store.hardwareCPUUsageRefreshSeconds = Int(number) }
        case "hardware.refresh.gpuUsage":
            if let number = Self.number(value) { store.hardwareGPUUsageRefreshSeconds = Int(number) }
        case "hardware.refresh.memory":
            if let number = Self.number(value) { store.hardwareMemoryRefreshSeconds = Int(number) }
        case "hardware.refresh.network":
            if let number = Self.number(value) { store.hardwareNetworkRefreshSeconds = Int(number) }
        case "hardware.refresh.temperature":
            if let number = Self.number(value) { store.hardwareTemperatureRefreshSeconds = Int(number) }
        case "hardware.refresh.disk":
            if let number = Self.number(value) { store.hardwareDiskRefreshSeconds = Int(number) }
        case "hardware.topApps.refreshSeconds":
            if let number = Self.number(value) { store.hardwareTopAppsRefreshSeconds = Int(number) }
        case "hardware.history.windowMinutes":
            if let number = Self.number(value) { store.hardwareHistoryWindowMinutes = Int(number) }
        case "hardware.network.downloadCapMbps":
            if let number = Self.number(value) { store.hardwareDownloadCapMbps = number }
        case "hardware.network.uploadCapMbps":
            if let number = Self.number(value) { store.hardwareUploadCapMbps = number }
        case "battery.thresholds.critical":
            if let number = Self.number(value) { store.batteryCriticalThreshold = number }
        case "battery.thresholds.full":
            if let number = Self.number(value) { store.batteryFullThreshold = number }
        case "battery.automation.autoLowPower":
            if case .bool(let flag) = value { store.autoEnablesLowPowerMode = flag }
        case "battery.automation.lowPowerThreshold":
            if let number = Self.number(value) { store.autoLowPowerThreshold = number }
        case "battery.powerFlow.enabled":
            if case .bool(let flag) = value { store.showsBatteryPowerFlow = flag }
        case "battery.powerInfoBar.enabled":
            if case .bool(let flag) = value { store.showsBatteryPowerInfoBar = flag }
        case "battery.highEnergyApps.enabled":
            if case .bool(let flag) = value { store.showsHighEnergyApps = flag }
        case "keepAwake.displayControl":
            if case .bool(let flag) = value { store.showsKeepScreenButton = flag }
        case "keepAwake.lidControl":
            if case .bool(let flag) = value { store.showsLidSleepButton = flag }
        case "keepAwake.allowLidSleepOnBattery":
            if case .bool(let flag) = value { store.allowLidSleepOnBattery = flag }
        case "keepAwake.autoDisableOnLowBattery":
            if case .bool(let flag) = value { store.autoDisableLidSleepOnLowBattery = flag }
        case "bluetooth.deviceList.enabled":
            if case .bool(let flag) = value { store.showsBluetoothDeviceList = flag }
        case "bluetooth.batteryLevels.enabled":
            if case .bool(let flag) = value { store.showsBluetoothBatteryLevels = flag }
        case "bluetooth.appleBattery.backgroundRefresh":
            if case .bool(let flag) = value { store.refreshesAppleBatteriesInBackground = flag }
        case "bluetooth.devices.hidden":
            store.hiddenBluetoothDeviceAddresses = Set(Self.strings(value))
        case "audio.output.maxVisibleDevices":
            if let number = Self.number(value) { store.maxVisibleOutputDevices = Int(number) }
        case "audio.output.showAllDevices":
            if case .bool(let flag) = value { store.alwaysShowsAllOutputDevices = flag }
        case "audio.input.maxVisibleDevices":
            if let number = Self.number(value) { store.maxVisibleInputDevices = Int(number) }
        case "audio.input.showAllDevices":
            if case .bool(let flag) = value { store.alwaysShowsAllInputDevices = flag }
        case "brightness.betterDisplay.combined":
            if case .bool(let flag) = value { store.useBetterDisplayCombinedBrightness = flag }
        case "icon.appIconPlacement":
            if case .string(let raw) = value, let parsed = AppIconPlacement(rawValue: raw) { store.appIconPlacement = parsed }
        case "icon.dockIconBackground":
            if case .string(let raw) = value, let parsed = DockIconBackgroundPreference(rawValue: raw) { store.dockIconBackgroundPreference = parsed }
        case "icon.airPodsRingFallback":
            if case .string(let raw) = value, let parsed = AirPodsRingFallback(rawValue: raw) { store.airPodsRingFallback = parsed }
        case "icon.cpuRingCenterContent":
            if case .string(let raw) = value, let parsed = HardwareRingCenterContent(rawValue: raw) { store.cpuRingCenterContent = parsed }
        case "icon.gpuRingCenterContent":
            if case .string(let raw) = value, let parsed = HardwareRingCenterContent(rawValue: raw) { store.gpuRingCenterContent = parsed }
        case "icon.ringStrokeStyle":
            if case .string(let raw) = value, let parsed = RingStrokeStyle(rawValue: raw) { store.ringStrokeStyle = parsed }
        case "icon.inputSourceMarkerStyle":
            if case .string(let raw) = value, let parsed = InputSourceMarkerStyle(rawValue: raw) { store.inputSourceMarkerStyle = parsed }
        case "audio.volumeDisplayStyle":
            if case .string(let raw) = value, let parsed = VolumeDisplayStyle(rawValue: raw) { store.volumeDisplayStyle = parsed }
        case "battery.bottomIndicatorStyle":
            if case .string(let raw) = value, let parsed = VolumeDisplayStyle(rawValue: raw) { store.batteryBottomIndicatorStyle = parsed }
        case "hardware.metricBottomIndicatorStyle":
            if case .string(let raw) = value, let parsed = VolumeDisplayStyle(rawValue: raw) { store.metricBottomIndicatorStyle = parsed }
        case "network.wifiBottomIndicatorStyle":
            if case .string(let raw) = value, let parsed = VolumeDisplayStyle(rawValue: raw) { store.wifiBottomIndicatorStyle = parsed }
        case "hardware.ring.memoryDisplayMode":
            if case .string(let raw) = value, let parsed = RingValueDisplayMode(rawValue: raw) { store.memoryRingDisplayMode = parsed }
        case "hardware.ring.ssdDisplayMode":
            if case .string(let raw) = value, let parsed = RingValueDisplayMode(rawValue: raw) { store.ssdRingDisplayMode = parsed }
        case "icon.localPluginDirectories":
            store.localIconPluginDirectories = Self.strings(value)
        case "hardware.ssd.externalVolumePaths":
            store.hardwareSSDExternalVolumePaths = Set(Self.strings(value))
        case "hardware.summaryMetrics":
            store.setEnabledHardwareSummaryMetrics(Set(Self.strings(value).compactMap { HardwareSummaryMetric(rawValue: $0) }))
        case "panel.modules.hardwareMonitor":
            if case .bool(let flag) = value { store.setPopupSection(.hardwareMonitor, enabled: flag) }
        case "audio.popup.naturalScrolling":
            if case .bool(let flag) = value { store.popupVolumeNaturalScrolling = flag }
        case "audio.popup.scrollAdjustsVolume":
            if case .bool(let flag) = value { store.popupPanelScrollAdjustsVolume = flag }
        case "audio.spatialControls.enabled":
            if case .bool(let flag) = value { store.showsSpatialAudioControls = flag }
        case "battery.appleBattery.refreshIntervalMinutes":
            if let number = Self.number(value) { store.appleBatteryRefreshIntervalMinutes = Int(number) }
        case "battery.appleDevicesAndBattery.enabled":
            if case .bool(let flag) = value { store.showsAppleDevicesAndBattery = flag }
        case "battery.bluetoothPowerControl.enabled":
            if case .bool(let flag) = value { store.showsBluetoothPowerControl = flag }
        case "battery.chargeToFullButton.enabled":
            if case .bool(let flag) = value { store.showsChargeToFullNowButton = flag }
        case "battery.chargeToFullRestoreLimit":
            if let number = Self.number(value) { store.chargeToFullRestoreLimit = number }
        case "battery.charging.boltHeartbeat":
            if case .bool(let flag) = value { store.showsChargingBoltHeartbeat = flag }
        case "battery.charging.dockEffect":
            if case .bool(let flag) = value { store.showsDockChargingEffect = flag }
        case "battery.charging.menuBarEffect":
            if case .bool(let flag) = value { store.showsMenuBarChargingEffect = flag }
        case "battery.confirmWiFiPowerOff":
            if case .bool(let flag) = value { store.confirmsWiFiPowerOff = flag }
        case "battery.highEnergyApps.refreshIntervalSeconds":
            if let number = Self.number(value) { store.highEnergyAppsRefreshIntervalSeconds = number }
        case "battery.marker.charging":
            if case .string(let raw) = value, let parsed = BatteryTopMarker(rawValue: raw) { store.batteryChargingMarker = parsed }
        case "battery.marker.connected":
            if case .string(let raw) = value, let parsed = BatteryTopMarker(rawValue: raw) { store.batteryConnectedMarker = parsed }
        case "battery.marker.noBattery":
            if case .string(let raw) = value, let parsed = BatteryTopMarker(rawValue: raw) { store.batteryNoBatteryMarker = parsed }
        case "battery.marker.onBattery":
            if case .string(let raw) = value, let parsed = BatteryTopMarker(rawValue: raw) { store.batteryOnBatteryMarker = parsed }
        case "battery.refreshInterval.onBattery":
            if let number = Self.number(value) { store.refreshIntervalOnBatterySeconds = number }
        case "battery.refreshInterval.onPower":
            if let number = Self.number(value) { store.refreshIntervalOnPowerSeconds = number }
        case "battery.simulateNoBattery":
            if case .bool(let flag) = value { store.simulatesNoBattery = flag }
        case "battery.splitGapProgress":
            if case .bool(let flag) = value { store.batterySplitGapProgress = flag }
        case "battery.statusColors.enabled":
            if case .bool(let flag) = value { store.usesBatteryStatusColors = flag }
        case "battery.symbolScale":
            if let number = Self.number(value) { store.batterySymbolScale = number }
        case "battery.wifiPowerControl.enabled":
            if case .bool(let flag) = value { store.showsWiFiPowerControl = flag }
        case "battery.automation.controlsLowPowerMode":
            if case .bool(let flag) = value { store.controlsLowPowerMode = flag }
        case "bluetooth.conversationAwarenessControls.enabled":
            if case .bool(let flag) = value { store.showsConversationAwarenessControls = flag }
        case "bluetooth.listeningMode.enabled":
            if case .bool(let flag) = value { store.showsBluetoothListeningMode = flag }
        case "bluetooth.listeningMode.previewDeviceCount":
            if let number = Self.number(value) { store.bluetoothListeningModePreviewDeviceCount = Int(number) }
        case "bluetooth.listeningMode.previewDeviceName":
            if case .string(let text) = value { store.bluetoothListeningModePreviewDeviceName = text }
        case "bluetooth.listeningMode.previewEnabled":
            if case .bool(let flag) = value { store.previewsBluetoothListeningMode = flag }
        case "bluetooth.listeningMode.previewLanguage":
            if case .string(let text) = value { store.bluetoothListeningModePreviewLanguage = text }
        case "bluetooth.maxVisibleDevices":
            if let number = Self.number(value) { store.maxVisibleBluetoothDevices = Int(number) }
        case "brightness.sliderMatchesBrightnessThickness":
            if case .bool(let flag) = value { store.panelLevelSliderMatchesBrightnessThickness = flag }
        case "hardware.ssd.includeExternalInPercent":
            if case .bool(let flag) = value { store.hardwareSSDIncludeExternalInPercent = flag }
        case "icon.airPods.ringUsesDualRing":
            if case .bool(let flag) = value { store.airPodsRingUsesDualRing = flag }
        case "icon.airPods.topSymbolInRing":
            if case .bool(let flag) = value { store.showsAirPodsTopSymbolInRing = flag }
        case "icon.network.wifiIconForEthernet":
            if case .bool(let flag) = value { store.showsWiFiIconForEthernet = flag }
        case "icon.network.wifiIconForHotspot":
            if case .bool(let flag) = value { store.showsWiFiIconForHotspot = flag }
        case "icon.network.wifiIconForInternetSharing":
            if case .bool(let flag) = value { store.showsWiFiIconForInternetSharing = flag }
        case "icon.network.wifiIconForTemporaryConnection":
            if case .bool(let flag) = value { store.showsWiFiIconForTemporaryConnection = flag }
        case "icon.outerRing.hardware.splitGapProgress":
            if case .bool(let flag) = value { store.hardwareRingSplitGapProgress = flag }
        case "icon.ring.monochromeCharging":
            if case .bool(let flag) = value { store.monochromeChargingRing = flag }
        case "network.chart.fixedScale":
            if case .bool(let flag) = value { store.hardwareNetworkChartFixedScale = flag }
        case "network.prioritizeErrors":
            if case .bool(let flag) = value { store.prioritizesNetworkErrors = flag }
        case "network.showLocalIPAddress":
            if case .bool(let flag) = value { store.showsLocalIPAddress = flag }
        case "network.symbolScale":
            if let number = Self.number(value) { store.wifiSymbolScale = number }
        case "panel.behavior.detailsAlongside":
            if case .bool(let flag) = value { store.showsPanelDetailsAlongside = flag }
        case "panel.behavior.scrollWheelStepPercent":
            if let number = Self.number(value) { store.popupScrollWheelStepPercent = number }
        case "panel.modules.enabled":
            let desired = Set(Self.strings(value).compactMap { PopupSection(rawValue: $0) })
            for section in PopupSection.allCases { store.setPopupSection(section, enabled: desired.contains(section)) }
        default:
            break
        }
    }

    func removeValue(for id: String) {
        // Core settings have typed defaults; there is no "unset" semantic here.
        // Restoring an absent value is a no-op and the store keeps its default.
    }

    func isFeatureEnabled(_ id: String) -> Bool { false }

    // MARK: - Value helpers

    private static func number(_ value: SettingsTransferValue) -> Double? {
        if case .number(let number) = value { return number }
        return nil
    }

    private static func strings(_ value: SettingsTransferValue) -> [String] {
        if case .array(let items) = value {
            return items.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
        }
        return []
    }
}

/// Builds a `SettingsService` backed by the live `SettingsStore`.
@MainActor
enum SettingsServiceFactory {
    static func make(for store: SettingsStore, appVersion: String? = nil) -> SettingsService {
        let registry = SettingsSemanticCatalog.makeRegistry(appVersion: appVersion)
        return SettingsService(registry: registry, provider: CoreSettingsProvider(store: store))
    }
}
