# Settings Inventory & Coverage Baseline

> **Repository base**: `origin/main` @ `7c125bf87dd8`  
> **Branch**: `feat/settings-semantic-infrastructure`  
> **Phase**: 0 (inventory baseline). Coverage opens at the baseline below and is updated as the semantic registry lands.

This document is the authoritative inventory of every persisted / user-visible setting surface in Status Trio. It is generated from the Swift sources (see *Method*) and reviewed per module. It intentionally does **not** treat the number of `SettingsPreferenceCatalog` entries as the total settings count.

## Method

- Enumerated every `@Published` property across `Sources/StatusTrioCore/Settings/*.swift` (the settings surface), every `static let *DefaultsKey` storage key, and every codec-backed (`Data`) persisted blob.
- Distinguished active persisted properties from **legacy-only** keys (stored keys no longer backing a `@Published` property, retained for migration) and **computed/derived** properties.
- Marked a property **UI-bound (user-visible)** when its name appears as a SwiftUI binding/`$`/member access in `Sources/StatusTrioCore/UI`. UI-visible settings are the coverage target for semantic definitions.
- Runtime snapshots, codec error state and migration inputs are classified as `internalState` and excluded from the writable user-settings surface, with reasons recorded below.

## Summary

| Metric | Count |
|---|---|
| `@Published` properties (settings surface) | 152 |
| UI-bound / user-visible properties | 128 |
| Persisted properties (UserDefaults or codec) | 144 |
| `*DefaultsKey` storage keys | 169 |
| Legacy-only storage keys (migration) | 25 |
| Computed / derived properties | 50 |

### By module

| Module | Properties |
|---|---|
| General / 通用 | 2 |
| Panel / 状态面板 | 13 |
| Icon / 图标 | 39 |
| Battery & Keep Awake / 电池与保持唤醒 | 38 |
| Hardware Monitor / 硬件监控 | 13 |
| Network / 网络 | 7 |
| Bluetooth & AirPods / 蓝牙与 AirPods | 18 |
| Audio / 音量与设备 | 16 |
| Brightness / 亮度 | 4 |
| Internal Runtime State / 内部运行状态 | 2 |

### By state class

| Class | Count | Meaning |
|---|---|---|
| `publicPreference` | 140 | 普通用户设置，可写、可描述 |
| `compositePreference` | 3 | 组合/虚拟设置（由多个底层字段或结构化 blob 表达） |
| `internalState` | 6 | 内部运行/迁移状态，不对用户暴露为可写设置 |
| `restricted` | 3 | 涉及权限、隐私或系统行为，需单独访问策略 |

## Coverage status

| Item | Phase 0 baseline | Target |
|---|---|---|
| User-visible settings with a semantic descriptor | 96 / 128 | 128 / 128 |
| Persisted properties with an explicit class | 152 / 152 (this doc) | 152 / 152 |
| Exclusions documented with reason | 100% listed below | 100% |

> `SettingsSemanticCatalog` currently describes 96 preferences (see `.agents/skills/status-trio-settings/references/settings-schema.json`). The remaining user-visible settings are the coverage backlog tracked by this inventory. See `docs/settings/settings-semantic-infrastructure.md` for the phase report.

## General / 通用

| Property | Type | Default | Storage key | Line | State | UI |
|---|---|---|---|---|---|---|
| `sharesAnonymousAnalytics` | `Bool` | `init` | `sharesAnonymousAnalytics` | SettingsStore.swift:406 | `restricted` | ✅ |
| `telemetryConsentVersion` | `Int` | `init` | `telemetryConsentVersion` | SettingsStore.swift:407 | `restricted` | ✅ |

## Panel / 状态面板

| Property | Type | Default | Storage key | Line | State | UI |
|---|---|---|---|---|---|---|
| `enabledPopupSections` | `Set<PopupSection>` | `init` | `enabledPopupSections` | SettingsStore.swift:1934 | `publicPreference` | ✅ |
| `keepsPanelOpenWhenOpeningSettings` | `Bool` | `init` | `keepsStatusPanelOpenWhenOpeningSettings` | SettingsStore.swift:2039 | `publicPreference` | ✅ |
| `menuBarRightClickAction` | `MenuBarRightClickAction` | `init` | `menuBarRightClickAction.v1` | SettingsStore.swift:506 | `publicPreference` | ✅ |
| `panelBackgroundStyle` | `PanelBackgroundStyle` | `init` | `panelBackgroundStyle` | SettingsStore.swift:494 | `publicPreference` | ✅ |
| `panelLevelSliderColor` | `PanelLevelSliderColorSelection` | `.default` | `panelLevelSliderColor` | SettingsStore.swift:518 | `publicPreference` | ✅ |
| `popupScrollWheelStepPercent` | `Double` | `init` | `popupScrollWheelStepPercent` | SettingsStore.swift:2066 | `publicPreference` | ✅ |
| `popupSectionOrder` | `[PopupSection]` | `init` | `popupSectionOrder` | SettingsStore.swift:1925 | `publicPreference` | ✅ |
| `returnsToSummaryOnOpen` | `Bool` | `init` | `returnsToSummaryOnOpen` | SettingsStore.swift:1975 | `publicPreference` | — |
| `showsPanelDetailsAlongside` | `Bool` | `init` | `showsPanelDetailsAlongside` | SettingsStore.swift:1992 | `publicPreference` | ✅ |
| `showsPanelOnHover` | `Bool` | `init` | `showsPanelOnHover` | SettingsStore.swift:2002 | `publicPreference` | ✅ |
| `statusPanelBoldTextEnabled` | `Bool` | `init` | `statusPanelBoldTextEnabled.v2` | SettingsStore.swift:2011 | `publicPreference` | ✅ |
| `statusPanelMediumTextEnabled` | `Bool` | `init` | `statusPanelMediumTextEnabled.v2` | SettingsStore.swift:2020 | `publicPreference` | ✅ |
| `statusPanelShortcut` | `StatusPanelShortcut?` | `init` | `statusPanelShortcut.v1` | SettingsStore.swift:408 | `restricted` | ✅ |

## Icon / 图标

| Property | Type | Default | Storage key | Line | State | UI |
|---|---|---|---|---|---|---|
| `_airPodsIconDeviceAddress` | `String?` | `init` | `—` | SettingsStore.swift:19 | `internalState` | — |
| `_connectedBluetoothIconDeviceAddress` | `String?` | `init` | `—` | SettingsStore.swift:22 | `internalState` | — |
| `_refreshesAirPodsBatteryForIcon` | `Bool` | `false` | `—` | SettingsStore.swift:25 | `internalState` | — |
| `airPodsRingFallback` | `AirPodsRingFallback` | `.battery` | `airPodsRingFallback` | SettingsStore.swift:1293 | `publicPreference` | ✅ |
| `airPodsRingUsesDualRing` | `Bool` | `true` | `airPodsRingUsesDualRing` | SettingsStore.swift:1282 | `publicPreference` | ✅ |
| `appIconPlacement` | `AppIconPlacement` | `init` | `appIconPlacement` | SettingsStore.swift:476 | `publicPreference` | ✅ |
| `bluetoothAudioIconChoiceRawValue` | `String` | `init` | `bluetoothAudioIconChoice` | SettingsStore.swift:1578 | `publicPreference` | — |
| `bluetoothIconColor` | `BluetoothIconColorSelection` | `init` | `bluetoothIconColor` | SettingsStore.swift:1030 | `publicPreference` | ✅ |
| `bluetoothNetworkIconDeviceAddress` | `String?` | `init` | `bluetoothNetworkIconDeviceAddress` | SettingsStore.swift:1902 | `publicPreference` | ✅ |
| `bluetoothNetworkIconSymbolName` | `String?` | `init` | `bluetoothNetworkIconSymbolName` | SettingsStore.swift:1916 | `publicPreference` | — |
| `bottomIndicatorSource` | `BottomIndicatorSource` | `init` | `bottomIndicatorSource` | SettingsStore.swift:1619 | `publicPreference` | ✅ |
| `connectionCenterSource` | `ConnectionCenterSource` | `init` | `connectionCenterSource` | SettingsStore.swift:1000 | `publicPreference` | ✅ |
| `cpuRingCenterContent` | `HardwareRingCenterContent` | `.temperature` | `cpuRingCenterContentV1` | SettingsStore.swift:1524 | `publicPreference` | ✅ |
| `dockIconBackgroundPreference` | `DockIconBackgroundPreference` | `init` | `dockIconBackgroundPreference` | SettingsStore.swift:482 | `publicPreference` | ✅ |
| `enabledHardwareRingSlots` | `Set<HardwareRingSlot>` | `init` | `enabledHardwareRingSlotsV1` | SettingsStore.swift:1435 | `publicPreference` | ✅ |
| `gpuRingCenterContent` | `HardwareRingCenterContent` | `.temperature` | `gpuRingCenterContentV1` | SettingsStore.swift:1530 | `publicPreference` | ✅ |
| `hardwareDiskRingColor` | `IconRGBA` | `HardwareRingColorConfiguration.solidStateDriveColor` | `hardwareDiskRingColorV1` | SettingsStore.swift:1334 | `publicPreference` | ✅ |
| `hardwareRingConfiguration` | `HardwareRingConfiguration` | `.default` | `hardwareRingConfigurationV1` | SettingsStore.swift:1302 | `publicPreference` | ✅ |
| `hardwareRingSplitGapProgress` | `Bool` | `false` | `hardwareRingSplitGapProgress` | SettingsStore.swift:1468 | `publicPreference` | ✅ |
| `hardwareTemperatureMonitoringEnabled` | `Bool` | `true` | `hardwareTemperatureMonitoringEnabledV1` | SettingsStore.swift:1511 | `publicPreference` | ✅ |
| `hasCompletedIconGuideOnboarding` | `Bool` | `init` | `hasCompletedIconGuideOnboarding.v1` | SettingsStore.swift:467 | `internalState` | ✅ |
| `iconConfiguration` | `IconConfigurationV1` | `.classic` | `iconConfigurationV1` | SettingsStore.swift:11 | `compositePreference` | — |
| `iconConfigurationLoadError` | `IconConfigurationCodecError?` | `init` | `—` | SettingsStore.swift:29 | `internalState` | — |
| `iconSize` | `Double` | `init` | `menuBarIconSize` | SettingsStore.swift:541 | `publicPreference` | ✅ |
| `iconSlotBindings` | `IconSlotBindingsV1` | `.classic` | `iconSlotBindingsV1` | SettingsStore.swift:37 | `compositePreference` | ✅ |
| `iconSlotBindingsLoadError` | `IconSlotBindingsCodecError?` | `init` | `—` | SettingsStore.swift:44 | `internalState` | — |
| `inputSourceMarkerStyle` | `InputSourceMarkerStyle` | `init` | `inputSourceMarkerStyle` | SettingsStore.swift:1013 | `publicPreference` | ✅ |
| `localIconPluginDirectories` | `[String]` | `[]` | `localIconPluginDirectories.v1` | SettingsStore.swift:52 | `compositePreference` | ✅ |
| `memoryRingDisplayMode` | `RingValueDisplayMode` | `init` | `memoryRingDisplayModeV1` | SettingsStore.swift:1455 | `publicPreference` | ✅ |
| `monochromeChargingRing` | `Bool?` | `init` | `monochromeChargingRing` | SettingsStore.swift:785 | `publicPreference` | ✅ |
| `outerRingContent` | `OuterRingContent` | `.systemBattery` | `outerRingContent` | SettingsStore.swift:1274 | `publicPreference` | ✅ |
| `ringStrokeStyle` | `RingStrokeStyle` | `init` | `ringStrokeStyle` | SettingsStore.swift:1681 | `publicPreference` | ✅ |
| `showsAirPodsTopSymbolInRing` | `Bool` | `true` | `showsAirPodsTopSymbolInRing` | SettingsStore.swift:1287 | `publicPreference` | ✅ |
| `showsHardwareRings` | `Bool` | `true` | `showsHardwareRings` | SettingsStore.swift:1411 | `publicPreference` | ✅ |
| `showsWiFiIconForEthernet` | `Bool` | `init` | `showsWiFiIconForEthernet` | SettingsStore.swift:937 | `publicPreference` | ✅ |
| `showsWiFiIconForHotspot` | `Bool` | `init` | `showsWiFiIconForHotspot` | SettingsStore.swift:946 | `publicPreference` | ✅ |
| `showsWiFiIconForInternetSharing` | `Bool` | `init` | `showsWiFiIconForInternetSharing` | SettingsStore.swift:964 | `publicPreference` | ✅ |
| `showsWiFiIconForTemporaryConnection` | `Bool` | `init` | `showsWiFiIconForTemporaryConnection` | SettingsStore.swift:955 | `publicPreference` | ✅ |
| `ssdRingDisplayMode` | `RingValueDisplayMode` | `init` | `ssdRingDisplayModeV1` | SettingsStore.swift:1460 | `publicPreference` | ✅ |

## Battery & Keep Awake / 电池与保持唤醒

| Property | Type | Default | Storage key | Line | State | UI |
|---|---|---|---|---|---|---|
| `allowLidSleepOnBattery` | `Bool` | `init` | `allowLidSleepOnBattery` | SettingsStore.swift:642 | `publicPreference` | ✅ |
| `appleBatteryRefreshIntervalMinutes` | `Int` | `init` | `appleBatteryRefreshIntervalMinutes` | SettingsStore.swift:1151 | `publicPreference` | ✅ |
| `autoDisableLidSleepOnLowBattery` | `Bool` | `init` | `autoDisableLidSleepOnLowBattery` | SettingsStore.swift:646 | `publicPreference` | ✅ |
| `autoEnablesLowPowerMode` | `Bool` | `init` | `autoEnablesLowPowerMode` | SettingsStore.swift:1120 | `publicPreference` | ✅ |
| `autoLowPowerThreshold` | `Double` | `init` | `autoLowPowerThreshold` | SettingsStore.swift:862 | `publicPreference` | ✅ |
| `batteryBottomIndicatorStyle` | `VolumeDisplayStyle` | `init` | `batteryBottomIndicatorStyle` | SettingsStore.swift:1658 | `publicPreference` | ✅ |
| `batteryChargingMarker` | `BatteryTopMarker` | `init` | `batteryChargingMarker` | SettingsStore.swift:586 | `publicPreference` | ✅ |
| `batteryConnectedMarker` | `BatteryTopMarker` | `init` | `batteryConnectedMarker` | SettingsStore.swift:594 | `publicPreference` | ✅ |
| `batteryCriticalThreshold` | `Double` | `init` | `batteryCriticalThreshold` | SettingsStore.swift:850 | `publicPreference` | ✅ |
| `batteryFullThreshold` | `Double` | `init` | `batteryFullThreshold` | SettingsStore.swift:878 | `publicPreference` | ✅ |
| `batteryNoBatteryMarker` | `BatteryTopMarker` | `init` | `batteryNoBatteryMarker` | SettingsStore.swift:603 | `publicPreference` | ✅ |
| `batteryOnBatteryMarker` | `BatteryTopMarker` | `init` | `batteryOnBatteryMarker` | SettingsStore.swift:578 | `publicPreference` | ✅ |
| `batterySplitGapProgress` | `Bool` | `init` | `batterySplitGapProgress` | SettingsStore.swift:736 | `publicPreference` | ✅ |
| `batteryStatusColors` | `BatteryStatusColors` | `init` | `batteryStatusColors.discharging` | SettingsStore.swift:813 | `publicPreference` | ✅ |
| `batterySymbolScale` | `Double` | `init` | `batterySymbolScale` | SettingsStore.swift:839 | `publicPreference` | ✅ |
| `chargeToFullRestoreLimit` | `Double` | `init` | `chargeToFullRestoreLimit` | SettingsStore.swift:897 | `publicPreference` | ✅ |
| `confirmsWiFiPowerOff` | `Bool` | `init` | `confirmsWiFiPowerOff` | SettingsStore.swift:1088 | `publicPreference` | ✅ |
| `controlsLowPowerMode` | `Bool` | `init` | `controlsLowPowerMode` | SettingsStore.swift:1111 | `publicPreference` | ✅ |
| `highEnergyAppsRefreshIntervalSeconds` | `Double` | `init` | `highEnergyAppsRefreshIntervalSeconds` | SettingsStore.swift:649 | `publicPreference` | ✅ |
| `refreshIntervalOnBatterySeconds` | `Double` | `init` | `statusRefreshIntervalOnBatterySeconds` | SettingsStore.swift:1701 | `publicPreference` | ✅ |
| `refreshIntervalOnPowerSeconds` | `Double` | `init` | `statusRefreshIntervalOnPowerSeconds` | SettingsStore.swift:1714 | `publicPreference` | ✅ |
| `showsAppleDevicesAndBattery` | `Bool` | `init` | `showsAppleDevicesAndBattery` | SettingsStore.swift:1138 | `publicPreference` | ✅ |
| `showsBatteryPowerFlow` | `Bool` | `init` | `showsBatteryPowerFlow` | SettingsStore.swift:622 | `publicPreference` | ✅ |
| `showsBatteryPowerInfoBar` | `Bool` | `init` | `showsBatteryPowerInfoBar` | SettingsStore.swift:627 | `publicPreference` | ✅ |
| `showsBluetoothBatteryLevels` | `Bool` | `init` | `showsBluetoothBatteryLevels` | SettingsStore.swift:1070 | `publicPreference` | ✅ |
| `showsBluetoothPowerControl` | `Bool` | `init` | `showsBluetoothPowerControl` | SettingsStore.swift:1097 | `publicPreference` | ✅ |
| `showsChargeToFullNowButton` | `Bool` | `init` | `showsChargeToFullNowButton` | SettingsStore.swift:671 | `publicPreference` | ✅ |
| `showsChargingBoltHeartbeat` | `Bool` | `init` | `showsChargingBoltHeartbeat` | SettingsStore.swift:724 | `publicPreference` | ✅ |
| `showsDockChargingEffect` | `Bool` | `init` | `showsDockChargingEffect` | SettingsStore.swift:702 | `publicPreference` | ✅ |
| `showsHighEnergyApps` | `Bool` | `init` | `showsHighEnergyApps` | SettingsStore.swift:630 | `publicPreference` | ✅ |
| `showsKeepScreenButton` | `Bool` | `init` | `showsKeepScreenButton` | SettingsStore.swift:634 | `publicPreference` | ✅ |
| `showsLidSleepButton` | `Bool` | `init` | `showsLidSleepButton` | SettingsStore.swift:638 | `publicPreference` | ✅ |
| `showsMenuBarChargingEffect` | `Bool` | `init` | `showsMenuBarChargingEffect` | SettingsStore.swift:690 | `publicPreference` | ✅ |
| `showsMobileDeviceBatteryLevels` | `Bool` | `init` | `showsMobileDeviceBatteryLevels` | SettingsStore.swift:1171 | `publicPreference` | — |
| `showsNearbyBluetoothBatteryDevices` | `Bool` | `init` | `showsNearbyBluetoothBatteryDevices` | SettingsStore.swift:1129 | `publicPreference` | — |
| `showsWiFiPowerControl` | `Bool` | `init` | `showsWiFiPowerControl` | SettingsStore.swift:1081 | `publicPreference` | ✅ |
| `simulatesNoBattery` | `Bool` | `init` | `simulatesNoBattery` | SettingsStore.swift:797 | `publicPreference` | ✅ |
| `usesBatteryStatusColors` | `Bool` | `init` | `usesBatteryStatusColors` | SettingsStore.swift:777 | `publicPreference` | ✅ |

## Hardware Monitor / 硬件监控

| Property | Type | Default | Storage key | Line | State | UI |
|---|---|---|---|---|---|---|
| `bottomIndicatorMetric` | `BottomIndicatorMetric` | `init` | `bottomIndicatorMetric` | SettingsStore.swift:1630 | `publicPreference` | ✅ |
| `enabledHardwareMonitorMetrics` | `Set<HardwareMonitorMetric>` | `init` | `enabledHardwareMonitorMetrics` | SettingsStore.swift:1952 | `publicPreference` | — |
| `enabledHardwareSummaryMetrics` | `Set<HardwareSummaryMetric>` | `init` | `enabledHardwareSummaryMetricsV1` | SettingsStore.swift:1445 | `publicPreference` | ✅ |
| `hardwareBackgroundHistoryEnabled` | `Bool` | `SettingsStore.defaultHardwareBackgroundHistoryEnabled` | `hardwareBackgroundHistoryEnabled` | SettingsStore.swift:1375 | `publicPreference` | ✅ |
| `hardwareHistoryWindowMinutes` | `Int` | `SettingsStore.defaultHardwareHistoryWindowMinutes` | `hardwareHistoryWindowMinutes` | SettingsStore.swift:1395 | `publicPreference` | ✅ |
| `hardwareMonitorMetricColors` | `[HardwareMonitorMetric: IconRGBA]` | `[:]` | `hardwareMonitorMetricColorsV1` | SettingsStore.swift:1320 | `publicPreference` | ✅ |
| `hardwareMonitorMetricOrder` | `[HardwareMonitorMetric]` | `init` | `hardwareMonitorMetricOrder` | SettingsStore.swift:1943 | `publicPreference` | — |
| `hardwarePanelRefreshSeconds` | `Int` | `SettingsStore.defaultHardwarePanelRefreshSeconds` | `hardwarePanelRefreshSeconds` | SettingsStore.swift:1383 | `publicPreference` | ✅ |
| `hardwareSSDIncludeExternalInPercent` | `Bool` | `false` | `hardwareSSDIncludeExternalInPercentV1` | SettingsStore.swift:1480 | `publicPreference` | ✅ |
| `metricBottomIndicatorStyle` | `VolumeDisplayStyle` | `init` | `metricBottomIndicatorStyle` | SettingsStore.swift:1642 | `publicPreference` | ✅ |
| `refreshIntervalSeconds` | `Double` | `init` | `statusRefreshIntervalSeconds` | SettingsStore.swift:1687 | `publicPreference` | — |
| `showsHardwareSummaryRow` | `Bool` | `true` | `showsHardwareSummaryRow` | SettingsStore.swift:1415 | `publicPreference` | ✅ |
| `showsHardwareTopApps` | `Bool` | `true` | `showsHardwareTopApps` | SettingsStore.swift:1422 | `publicPreference` | ✅ |

## Network / 网络

| Property | Type | Default | Storage key | Line | State | UI |
|---|---|---|---|---|---|---|
| `hardwareDownloadCapMbps` | `Double` | `SettingsStore.defaultHardwareDownloadCapMbps` | `hardwareDownloadCapMbps` | SettingsStore.swift:1357 | `publicPreference` | ✅ |
| `hardwareNetworkChartFixedScale` | `Bool` | `false` | `hardwareNetworkChartFixedScale` | SettingsStore.swift:1428 | `publicPreference` | ✅ |
| `hardwareUploadCapMbps` | `Double` | `SettingsStore.defaultHardwareUploadCapMbps` | `hardwareUploadCapMbps` | SettingsStore.swift:1365 | `publicPreference` | ✅ |
| `prioritizesNetworkErrors` | `Bool` | `init` | `prioritizesNetworkErrors` | SettingsStore.swift:1022 | `publicPreference` | ✅ |
| `showsLocalIPAddress` | `Bool` | `init` | `showsLocalIPAddress` | SettingsStore.swift:973 | `publicPreference` | ✅ |
| `wifiBottomIndicatorStyle` | `VolumeDisplayStyle` | `init` | `wifiBottomIndicatorStyle` | SettingsStore.swift:1650 | `publicPreference` | ✅ |
| `wifiSymbolScale` | `Double` | `init` | `wifiSymbolScale` | SettingsStore.swift:1591 | `publicPreference` | ✅ |

## Bluetooth & AirPods / 蓝牙与 AirPods

| Property | Type | Default | Storage key | Line | State | UI |
|---|---|---|---|---|---|---|
| `archivedLegacyNearbyBLESelections` | `[NearbyBLEDeviceSelection]` | `init` | `archivedLegacyNearbyBLESelections` | SettingsStore.swift:1162 | `publicPreference` | — |
| `bluetoothDeviceOrder` | `[String]` | `init` | `bluetoothDeviceOrder` | SettingsStore.swift:1860 | `publicPreference` | ✅ |
| `bluetoothListeningModePreviewDeviceCount` | `Int` | `init` | `bluetoothListeningModePreviewDeviceCount` | SettingsStore.swift:1241 | `publicPreference` | ✅ |
| `bluetoothListeningModePreviewDeviceName` | `String` | `init` | `bluetoothListeningModePreviewDeviceName` | SettingsStore.swift:1229 | `publicPreference` | ✅ |
| `bluetoothListeningModePreviewLanguage` | `String` | `init` | `bluetoothListeningModePreviewLanguage` | SettingsStore.swift:1262 | `publicPreference` | ✅ |
| `bluetoothVolumeColor` | `BluetoothVolumeColorSelection` | `.automatic` | `bluetoothVolumeColor` | SettingsStore.swift:1049 | `publicPreference` | ✅ |
| `hiddenBluetoothDeviceAddresses` | `Set<String>` | `init` | `hiddenBluetoothDeviceAddresses` | SettingsStore.swift:1879 | `publicPreference` | ✅ |
| `hidesGhostBluetoothDevices` | `Bool` | `init` | `hidesGhostBluetoothDevices` | SettingsStore.swift:1873 | `publicPreference` | — |
| `maxVisibleBluetoothDevices` | `Int` | `init` | `maxVisibleBluetoothDevices` | SettingsStore.swift:1849 | `publicPreference` | ✅ |
| `nearbyBLESelections` | `[NearbyBLEDeviceSelection]` | `init` | `nearbyBLEConsent.v1` | SettingsStore.swift:1866 | `publicPreference` | ✅ |
| `previewsBluetoothListeningMode` | `Bool` | `init` | `previewsBluetoothListeningMode` | SettingsStore.swift:1204 | `publicPreference` | ✅ |
| `refreshesAppleBatteriesInBackground` | `Bool` | `init` | `refreshesAppleBatteriesInBackground` | SettingsStore.swift:1142 | `publicPreference` | ✅ |
| `revealedGhostBluetoothDeviceAddresses` | `Set<String>` | `init` | `revealedGhostBluetoothDeviceAddresses` | SettingsStore.swift:1889 | `publicPreference` | — |
| `showsBluetoothDeviceList` | `Bool` | `init` | `showsBluetoothDeviceList` | SettingsStore.swift:1840 | `publicPreference` | ✅ |
| `showsBluetoothListeningMode` | `Bool` | `init` | `showsBluetoothListeningMode` | SettingsStore.swift:1187 | `publicPreference` | ✅ |
| `showsConversationAwarenessControls` | `Bool` | `init` | `showsConversationAwarenessControls` | SettingsStore.swift:991 | `publicPreference` | ✅ |
| `trustedAppleDeviceMetadata` | `[AppleDeviceCandidate]` | `init` | `trustedAppleDeviceMetadata.v1` | SettingsStore.swift:1164 | `publicPreference` | ✅ |
| `usesBluetoothAudioVolumeColor` | `Bool` | `init` | `usesBluetoothAudioVolumeColor` | SettingsStore.swift:1039 | `publicPreference` | — |

## Audio / 音量与设备

| Property | Type | Default | Storage key | Line | State | UI |
|---|---|---|---|---|---|---|
| `alwaysShowsAllInputDevices` | `Bool` | `init` | `alwaysShowsAllInputDevices` | SettingsStore.swift:1756 | `publicPreference` | ✅ |
| `alwaysShowsAllOutputDevices` | `Bool` | `init` | `alwaysShowsAllOutputDevices` | SettingsStore.swift:1736 | `publicPreference` | ✅ |
| `externalVolumeConfigurations` | `[String: ExternalVolumeConfiguration]` | `init` | `externalVolumeConfigurations.v1` | SettingsStore.swift:1793 | `publicPreference` | — |
| `hardwareSSDExternalVolumePaths` | `Set<String>` | `[]` | `hardwareSSDExternalVolumePathsV1` | SettingsStore.swift:1492 | `publicPreference` | ✅ |
| `hiddenInputDeviceUIDs` | `Set<String>` | `init` | `hiddenInputDeviceUIDs` | SettingsStore.swift:1787 | `publicPreference` | ✅ |
| `hiddenOutputDeviceUIDs` | `Set<String>` | `init` | `hiddenOutputDeviceUIDs` | SettingsStore.swift:1773 | `publicPreference` | ✅ |
| `inputDeviceOrder` | `[String]` | `init` | `inputDeviceOrder` | SettingsStore.swift:1779 | `publicPreference` | — |
| `maxVisibleInputDevices` | `Int` | `init` | `maxVisibleInputDevices` | SettingsStore.swift:1745 | `publicPreference` | ✅ |
| `maxVisibleOutputDevices` | `Int` | `init` | `maxVisibleOutputDevices` | SettingsStore.swift:1725 | `publicPreference` | ✅ |
| `outputDeviceOrder` | `[String]` | `init` | `outputDeviceOrder` | SettingsStore.swift:1765 | `publicPreference` | — |
| `popupPanelScrollAdjustsVolume` | `Bool` | `init` | `popupPanelScrollAdjustsVolume` | SettingsStore.swift:1966 | `publicPreference` | ✅ |
| `popupVolumeNaturalScrolling` | `Bool` | `init` | `popupVolumeNaturalScrolling` | SettingsStore.swift:2057 | `publicPreference` | ✅ |
| `popupVolumeScrollDirection` | `PopupVolumeScrollDirection` | `init` | `popupVolumeScrollDirection` | SettingsStore.swift:2048 | `publicPreference` | — |
| `popupVolumeScrollFeedbackOverride` | `Bool?` | `init` | `—` | SettingsStore.swift:2079 | `publicPreference` | — |
| `showsSpatialAudioControls` | `Bool` | `init` | `showsSpatialAudioControls` | SettingsStore.swift:982 | `publicPreference` | ✅ |
| `volumeDisplayStyle` | `VolumeDisplayStyle` | `init` | `volumeDisplayStyle` | SettingsStore.swift:1609 | `publicPreference` | ✅ |

## Brightness / 亮度

| Property | Type | Default | Storage key | Line | State | UI |
|---|---|---|---|---|---|---|
| `externalBrightnessConfigurations` | `[String: ExternalBrightnessConfiguration]` | `init` | `externalBrightnessConfigurations.v1` | SettingsStore.swift:1805 | `publicPreference` | — |
| `hiddenBrightnessDisplayIDs` | `Set<String>` | `init` | `hiddenBrightnessDisplayIDs` | SettingsStore.swift:1819 | `publicPreference` | ✅ |
| `panelLevelSliderMatchesBrightnessThickness` | `Bool` | `false` | `panelLevelSliderMatchesBrightnessThickness` | SettingsStore.swift:531 | `publicPreference` | ✅ |
| `useBetterDisplayCombinedBrightness` | `Bool` | `init` | `useBetterDisplayCombinedBrightness` | SettingsStore.swift:1831 | `publicPreference` | ✅ |

## Internal Runtime State / 内部运行状态

| Property | Type | Default | Storage key | Line | State | UI |
|---|---|---|---|---|---|---|
| `lastBackupURL` | `URL?` | `init` | `—` | SettingsTransferSession.swift:21 | `publicPreference` | ✅ |
| `preview` | `SettingsTransferPreview?` | `init` | `—` | SettingsTransferSession.swift:20 | `publicPreference` | ✅ |

## Legacy & migration-only storage keys

These keys are still read for migration/data continuity but are **not** the authority for a writable user setting. They must remain readable; they must not be exposed as ordinary writable settings.

| Key constant | Stored key | File:Line |
|---|---|---|
| `sparkleHasLaunchedBefore` | `SUHasLaunchedBefore` | SettingsStore.swift:63 |
| `airPodsIconDeviceAddress` | `airPodsIconDeviceAddress` | SettingsStore+IconCompatibility.swift:194 |
| `appleDeviceSelections` | `appleDeviceSelections` | SettingsStore.swift:190 |
| `appleDeviceSettingsMigrationVersion` | `appleDeviceSettingsMigrationVersion` | SettingsStore.swift:191 |
| `batteryConnectedIndicator` | `batteryConnectedIndicator` | SettingsStore.swift:109 |
| `batteryStatusColorsCharging` | `batteryStatusColors.charging` | SettingsStore.swift:122 |
| `batteryStatusColorsCritical` | `batteryStatusColors.critical` | SettingsStore.swift:125 |
| `batteryStatusColorsHighPower` | `batteryStatusColors.highPower` | SettingsStore.swift:124 |
| `batteryStatusColorsLowPower` | `batteryStatusColors.lowPower` | SettingsStore.swift:123 |
| `bluetoothSymbolScale` | `bluetoothSymbolScale` | SettingsStore.swift:205 |
| `connectedBluetoothIconDeviceAddress` | `connectedBluetoothIconDeviceAddress` | SettingsStore+IconCompatibility.swift:195 |
| `hasSeenIconGuide` | `hasSeenIconGuide` | SettingsStore.swift:59 |
| `nearbyBLESelections` | `nearbyBLESelections` | SettingsStore.swift:310 |
| `legacyPopupScrollAdjustsVolume` | `popupScrollAdjustsVolume` | SettingsStore.swift:357 |
| `legacyPopupVolumeScrollScope` | `popupVolumeScrollScope` | SettingsStore.swift:358 |
| `prioritizesNetworkErrorsOverBluetoothAudio` | `prioritizesNetworkErrorsOverBluetoothAudio` | SettingsStore.swift:176 |
| `prioritizesNetworkErrorsOverInputSource` | `prioritizesNetworkErrorsOverInputSource` | SettingsStore.swift:171 |
| `refreshesAirPodsBatteryForIcon` | `refreshesAirPodsBatteryForIcon` | SettingsStore+IconCompatibility.swift:196 |
| `replacesNetworkIconWithBluetoothAudio` | `replacesNetworkIconWithBluetoothAudio` | SettingsStore.swift:172 |
| `showsBatteryPercentage` | `showsBatteryPercentage` | SettingsStore.swift:88 |
| `showsBatteryPercentageInConnectionSlot` | `showsBatteryPercentageInConnectionSlot` | SettingsStore.swift:147 |
| `showsChargingEffect` | `showsChargingEffect` | SettingsStore.swift:104 |
| `showsChargingIndicator` | `showsChargingIndicator` | SettingsStore.swift:102 |
| `showsInlineAirPodsControls` | `showsInlineAirPodsControls` | SettingsStore.swift:144 |
| `showsPercentageWhenConnected` | `showsPercentageWhenConnected` | SettingsStore.swift:112 |

> Note: a few entries above (e.g. `batteryStatusColors.*`, `appleDeviceSelections`, `nearbyBLESelections`) are component keys of a composite property and are listed here only for completeness; the composite property is the semantic authority.

## Composite / codec-backed settings

| Setting | Underlying representation | Authority |
|---|---|---|
| `iconConfiguration` | `IconConfigurationV1` encoded as `Data` (`IconConfigurationCodec`) | authoritative icon config blob |
| `iconSlotBindings` | `IconSlotBindingsV1` encoded as `Data` (`IconSlotBindingsCodec`) | slot bindings blob; must stay in sync with source settings |
| `localIconPluginDirectories` | `[String]` directory paths | explicit plugin opt-in |

## Exclusions (not ordinary writable user settings)

| Surface | Class | Reason |
|---|---|---|
| Properties prefixed `_` (e.g. `_airPodsIconDeviceAddress`) | internalState | device-identity/runtime cache, not a preference |
| `*LoadError` properties | internalState | codec decode error state |
| `hasCompletedIconGuideOnboarding`, `hasSeenIconGuide` | internalState | onboarding progress, not user preference |
| `sharesAnonymousAnalytics`, `telemetryConsentVersion` | restricted | privacy/telemetry consent, separate access policy; never auto-modified |
| `statusPanelShortcut` | restricted | global shortcut, device/OS-scoped, excluded from transfer |
| `lastBackupURL`, `preview` | internalState | transient runtime state |
| Legacy storage keys (see table above) | legacy | migration/data continuity only |
| `SettingsPreferenceCatalog` allowlist | — | export/import allowlist is deliberately narrower than persistence; unrelated to this inventory's writability |

## Source references

- `Sources/StatusTrioCore/Settings/SettingsStore.swift`
- `Sources/StatusTrioCore/Settings/SettingsStore+IconAppearance.swift`
- `Sources/StatusTrioCore/Settings/SettingsStore+IconCompatibility.swift`
- `Sources/StatusTrioCore/Settings/SettingsStore+IconPresentation.swift`
- `Sources/StatusTrioCore/Settings/SettingsStore+LocalIconPlugins.swift`
- `Sources/StatusTrioCore/Settings/SettingsPreferenceCatalog.swift`
- `Sources/StatusTrioCore/Settings/SettingsTransferDocument.swift`
- `Sources/StatusTrioCore/Settings/SettingsTransferSession.swift`
- `Sources/StatusTrioCore/Settings/SettingsTransferValue.swift`

