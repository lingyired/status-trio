import Foundation

/// The portable part of SettingsStore, deliberately independent of its defaults
/// domain. Adding a persisted property does not silently make it transferable.
///
/// Helper opt-in, consent, telemetry, onboarding, shortcuts, development/test
/// state, migration inputs and device identities are not portable. Language
/// belongs to Localization and is handled by the transfer document/session.
@MainActor
enum SettingsPreferenceCatalog {
    private typealias Value = SettingsTransferValue

    private struct Preference {
        let key: String
        let defaultValue: Value
        let read: @MainActor (SettingsStore) -> Value
        let isValid: @MainActor (Value) -> Bool
        let write: @MainActor (Value, SettingsStore) -> Void
    }

    static func snapshot(_ store: SettingsStore) -> [String: SettingsTransferValue] {
        Dictionary(uniqueKeysWithValues: preferences.map { ($0.key, $0.read(store)) })
    }

    /// Validates everything before callers mutate live state. Missing keys stay
    /// missing; invalid known keys use the shipped fallback, never a clamp or a
    /// coercion. Warning text includes keys only, not private imported values.
    static func prepare(_ values: [String: SettingsTransferValue]) -> (
        values: [String: SettingsTransferValue], warnings: [String]
    ) {
        let catalog = Dictionary(uniqueKeysWithValues: preferences.map { ($0.key, $0) })
        var result: [String: Value] = [:]
        var warnings: [String] = []
        for key in values.keys.sorted() {
            guard let preference = catalog[key] else {
                warnings.append("Unknown preference: \(key)")
                continue
            }
            guard let value = values[key] else { continue }
            if key == "batteryStatusColors", case let .object(roles) = value {
                let prepared = prepareBatteryColors(roles)
                result[key] = .object(prepared.values)
                warnings.append(contentsOf: prepared.warnings)
            } else if preference.isValid(value) {
                result[key] = value
            } else {
                result[key] = preference.defaultValue
                warnings.append("Invalid preference; using default: \(key)")
            }
        }
        return (result, warnings)
    }

    static func apply(_ values: [String: SettingsTransferValue], to store: SettingsStore) {
        let prepared = prepare(values).values
        for preference in preferences {
            guard let value = prepared[preference.key] else { continue }
            preference.write(value, store)
        }
    }

    // These defaults mirror a fresh SettingsStore initializer without creating
    // a store, running migration, reading system settings or touching defaults.
    private static var preferences: [Preference] {
        generalPreferences + iconPreferences + batteryPreferences + networkAndAudioPreferences
            + bluetoothPreferences + brightnessPreferences + panelPreferences
    }

    private static var brightnessPreferences: [Preference] {
        [
            boolean(
                "useBetterDisplayCombinedBrightness",
                \.useBetterDisplayCombinedBrightness,
                default: false
            )
        ]
    }

    private static var generalPreferences: [Preference] {
        [
            enumeration("appIconPlacement", \.appIconPlacement, default: .menuBar),
            enumeration("dockIconBackgroundPreference", \.dockIconBackgroundPreference, default: .system),
            enumeration("panelBackgroundStyle", \.panelBackgroundStyle, default: PanelBackgroundStyle.systemDefault),
            panelLevelSliderColorPreference,
            boolean(
                "panelLevelSliderMatchesBrightnessThickness",
                \.panelLevelSliderMatchesBrightnessThickness,
                default: false
            ),
            enumeration("menuBarRightClickAction", \.menuBarRightClickAction, default: .contextMenu),
            number("refreshIntervalOnBatterySeconds", \.refreshIntervalOnBatterySeconds,
                   default: SettingsStore.defaultRefreshIntervalSeconds, range: SettingsStore.refreshIntervalRange, step: 1),
            number("refreshIntervalOnPowerSeconds", \.refreshIntervalOnPowerSeconds,
                   default: SettingsStore.defaultRefreshIntervalSeconds, range: SettingsStore.refreshIntervalRange, step: 1)
        ]
    }

    private static var iconPreferences: [Preference] {
        [
            number("iconSize", \.iconSize, default: SettingsStore.defaultIconSize, range: SettingsStore.iconSizeRange),
            number("batterySymbolScale", \.batterySymbolScale,
                   default: SettingsStore.defaultBatterySymbolScale, range: SettingsStore.batterySymbolScaleRange),
            number("wifiSymbolScale", \.wifiSymbolScale,
                   default: SettingsStore.defaultWifiSymbolScale, range: SettingsStore.wifiSymbolScaleRange),
            enumeration("batteryOnBatteryMarker", \.batteryOnBatteryMarker,
                        default: .percentage, allowed: BatteryTopMarker.onBatteryOptions),
            enumeration("batteryChargingMarker", \.batteryChargingMarker, default: .bolt),
            enumeration("batteryConnectedMarker", \.batteryConnectedMarker, default: .plug),
            enumeration("batteryNoBatteryMarker", \.batteryNoBatteryMarker,
                        default: .plug, allowed: BatteryTopMarker.noBatteryOptions),
            boolean("showsMenuBarChargingEffect", \.showsMenuBarChargingEffect, default: true),
            boolean("showsDockChargingEffect", \.showsDockChargingEffect, default: true),
            boolean("showsChargingBoltHeartbeat", \.showsChargingBoltHeartbeat, default: true),
            boolean("batterySplitGapProgress", \.batterySplitGapProgress, default: false),
            boolean("usesBatteryStatusColors", \.usesBatteryStatusColors, default: true),
            optionalBoolean("monochromeChargingRing", \.monochromeChargingRing),
            batteryColorsPreference,
            enumeration("connectionCenterSource", \.connectionCenterSource, default: .network),
            enumeration("inputSourceMarkerStyle", \.inputSourceMarkerStyle, default: .systemIcon),
            boolean("prioritizesNetworkErrors", \.prioritizesNetworkErrors, default: true),
            bluetoothColorPreference,
            mapped("bluetoothAudioIconChoiceRawValue", \.bluetoothAudioIconChoiceRawValue,
                   default: BluetoothAudioIconChoice.automatic.rawValue,
                   decode: { value in
                       guard case let .string(raw) = value, BluetoothAudioIconChoice(rawValue: raw) != nil else { return nil }
                       return raw
                   }, encode: { .string($0) }),
            boolean("usesBluetoothAudioVolumeColor", \.usesBluetoothAudioVolumeColor, default: false),
            mapped("bluetoothVolumeColor", \.bluetoothVolumeColor, default: BluetoothVolumeColorSelection.default, decode: { value in guard case let .string(raw) = value else { return nil }; let parsed = BluetoothVolumeColorSelection(storageValue: raw); return parsed.storageValue == raw ? parsed : nil }, encode: { .string($0.storageValue) }),
            enumeration("volumeDisplayStyle", \.volumeDisplayStyle, default: SettingsStore.defaultVolumeDisplayStyle),
            enumeration("wifiBottomIndicatorStyle", \.wifiBottomIndicatorStyle,
                        default: SettingsStore.defaultWifiBottomIndicatorStyle),
            enumeration("batteryBottomIndicatorStyle", \.batteryBottomIndicatorStyle,
                        default: SettingsStore.defaultBatteryBottomIndicatorStyle),
            enumeration("metricBottomIndicatorStyle", \.metricBottomIndicatorStyle,
                        default: SettingsStore.defaultMetricBottomIndicatorStyle),
            enumeration("ringStrokeStyle", \.ringStrokeStyle, default: SettingsStore.defaultRingStrokeStyle),
            slotBindingsPreference
        ]
    }

    private static var batteryPreferences: [Preference] {
        [
            boolean("showsBatteryPowerFlow", \.showsBatteryPowerFlow, default: true),
            boolean("showsBatteryPowerInfoBar", \.showsBatteryPowerInfoBar, default: false),
            boolean("showsHighEnergyApps", \.showsHighEnergyApps, default: false),
            number("highEnergyAppsRefreshIntervalSeconds", \.highEnergyAppsRefreshIntervalSeconds,
                   default: SettingsStore.defaultHighEnergyAppsRefreshIntervalSeconds,
                   range: SettingsStore.highEnergyAppsRefreshIntervalRange, step: 5),
            boolean("showsChargeToFullNowButton", \.showsChargeToFullNowButton, default: true),
            boolean("showsLegacyChargeToFullButton", \.showsLegacyChargeToFullButton, default: false),
            enumeration("legacySleepPolicy", \.legacySleepPolicy, default: .pauseCharging),
            number("batteryCriticalThreshold", \.batteryCriticalThreshold,
                   default: SettingsStore.defaultBatteryCriticalThreshold, range: SettingsStore.batteryCriticalThresholdRange, step: 1),
            number("autoLowPowerThreshold", \.autoLowPowerThreshold,
                   default: SettingsStore.defaultAutoLowPowerThreshold, range: SettingsStore.autoLowPowerThresholdRange, step: 1),
            number("batteryFullThreshold", \.batteryFullThreshold,
                   default: SettingsStore.defaultBatteryFullThreshold, range: SettingsStore.batteryFullThresholdRange, step: 1),
            boolean("autoEnablesLowPowerMode", \.autoEnablesLowPowerMode, default: false)
        ]
    }

    private static var networkAndAudioPreferences: [Preference] {
        [
            boolean("showsWiFiIconForEthernet", \.showsWiFiIconForEthernet, default: false),
            boolean("showsWiFiIconForHotspot", \.showsWiFiIconForHotspot, default: false),
            boolean("showsWiFiIconForTemporaryConnection", \.showsWiFiIconForTemporaryConnection, default: false),
            boolean("showsWiFiIconForInternetSharing", \.showsWiFiIconForInternetSharing, default: false),
            boolean("showsLocalIPAddress", \.showsLocalIPAddress, default: false),
            boolean("showsWiFiPowerControl", \.showsWiFiPowerControl, default: true),
            boolean("confirmsWiFiPowerOff", \.confirmsWiFiPowerOff, default: true),
            boolean("showsSpatialAudioControls", \.showsSpatialAudioControls, default: true),
            boolean("showsConversationAwarenessControls", \.showsConversationAwarenessControls, default: true),
            integer("maxVisibleOutputDevices", \.maxVisibleOutputDevices,
                    default: SettingsStore.defaultMaxVisibleOutputDevices, range: SettingsStore.outputDeviceLimitRange),
            boolean("alwaysShowsAllOutputDevices", \.alwaysShowsAllOutputDevices, default: false),
            integer("maxVisibleInputDevices", \.maxVisibleInputDevices,
                    default: SettingsStore.defaultMaxVisibleInputDevices, range: SettingsStore.inputDeviceLimitRange),
            boolean("alwaysShowsAllInputDevices", \.alwaysShowsAllInputDevices, default: false)
        ]
    }

    private static var bluetoothPreferences: [Preference] {
        [
            boolean("showsBluetoothBatteryLevels", \.showsBluetoothBatteryLevels, default: true),
            boolean("showsBluetoothPowerControl", \.showsBluetoothPowerControl, default: true),
            boolean("showsAppleDevicesAndBattery", \.showsAppleDevicesAndBattery, default: false),
            boolean("refreshesAppleBatteriesInBackground", \.refreshesAppleBatteriesInBackground, default: false),
            integer("appleBatteryRefreshIntervalMinutes", \.appleBatteryRefreshIntervalMinutes,
                    default: SettingsStore.defaultAppleBatteryRefreshIntervalMinutes,
                    range: SettingsStore.appleBatteryRefreshIntervalMinutesRange),
            boolean("showsBluetoothListeningMode", \.showsBluetoothListeningMode, default: true),
            boolean("showsBluetoothDeviceList", \.showsBluetoothDeviceList, default: true),
            boolean("hidesGhostBluetoothDevices", \.hidesGhostBluetoothDevices, default: true),
            integer("maxVisibleBluetoothDevices", \.maxVisibleBluetoothDevices,
                    default: SettingsStore.defaultMaxVisibleBluetoothDevices, range: SettingsStore.bluetoothDeviceLimitRange)
        ]
    }

    private static var panelPreferences: [Preference] {
        [
            popupOrderPreference,
            enabledSectionsPreference,
            boolean("popupPanelScrollAdjustsVolume", \.popupPanelScrollAdjustsVolume,
                    default: SettingsStore.defaultPopupPanelScrollAdjustsVolume),
            boolean("returnsToSummaryOnOpen", \.returnsToSummaryOnOpen, default: false),
            boolean("showsPanelDetailsAlongside", \.showsPanelDetailsAlongside, default: false),
            boolean("showsPanelOnHover", \.showsPanelOnHover, default: false),
            number("popupScrollWheelStepPercent", \.popupScrollWheelStepPercent,
                   default: SettingsStore.defaultPopupScrollWheelStepPercent,
                   range: SettingsStore.popupScrollWheelStepPercentRange, step: 0.5),
            boolean("popupVolumeNaturalScrolling", \.popupVolumeNaturalScrolling,
                    default: SettingsStore.defaultPopupVolumeNaturalScrolling),
            optionalBoolean("popupVolumeScrollFeedbackOverride", \.popupVolumeScrollFeedbackOverride),
            boolean("hardwareBackgroundHistoryEnabled", \.hardwareBackgroundHistoryEnabled,
                    default: SettingsStore.defaultHardwareBackgroundHistoryEnabled),
            integer("hardwarePanelRefreshSeconds", \.hardwarePanelRefreshSeconds,
                    default: SettingsStore.defaultHardwarePanelRefreshSeconds, range: 1...8),
            integer("hardwareHistoryWindowMinutes", \.hardwareHistoryWindowMinutes,
                    default: SettingsStore.defaultHardwareHistoryWindowMinutes,
                    range: 1...5),
            boolean("hardwareNetworkChartFixedScale", \.hardwareNetworkChartFixedScale, default: false),
            number("hardwareDownloadCapMbps", \.hardwareDownloadCapMbps,
                   default: SettingsStore.defaultHardwareDownloadCapMbps,
                   range: SettingsStore.hardwareSpeedCapRange, step: 1),
            number("hardwareUploadCapMbps", \.hardwareUploadCapMbps,
                   default: SettingsStore.defaultHardwareUploadCapMbps,
                   range: SettingsStore.hardwareSpeedCapRange, step: 1),
            boolean("showsHardwareRings", \.showsHardwareRings, default: true),
            boolean("showsHardwareSummaryRow", \.showsHardwareSummaryRow, default: true),
            boolean("showsHardwareTopApps", \.showsHardwareTopApps, default: true),
            enabledHardwareRingSlotsPreference,
            enabledHardwareSummaryMetricsPreference,
            enumeration("memoryRingDisplayMode", \.memoryRingDisplayMode,
                        default: .used, allowed: RingValueDisplayMode.allCases),
            enumeration("ssdRingDisplayMode", \.ssdRingDisplayMode,
                        default: .used, allowed: RingValueDisplayMode.allCases),
            boolean("hardwareRingSplitGapProgress", \.hardwareRingSplitGapProgress, default: false),
            boolean("hardwareTemperatureMonitoringEnabled",
                    \.hardwareTemperatureMonitoringEnabled, default: true),
            // Apply the temperature switch before restoring the metric it makes available.
            enumeration("bottomIndicatorMetric", \.bottomIndicatorMetric,
                        default: SettingsStore.defaultBottomIndicatorMetric,
                        allowed: BottomIndicatorMetric.allCases.filter { $0.hardwareMetric?.usesStatusSnapshot != true }),
            enumeration("cpuRingCenterContent", \.cpuRingCenterContent,
                        default: .temperature, allowed: HardwareRingCenterContent.allCases),
            enumeration("gpuRingCenterContent", \.gpuRingCenterContent,
                        default: .temperature, allowed: HardwareRingCenterContent.allCases)
            // Appearance-only ring colours (hardwareMonitorMetricColors and
            // hardwareDiskRingColor) are intentionally excluded from settings
            // transfer: they are per-surface cosmetics, not portable preferences.
        ]
    }

    private static func mapped<T>(
        _ key: String, _ path: ReferenceWritableKeyPath<SettingsStore, T>, default defaultValue: T,
        decode: @escaping @MainActor (Value) -> T?, encode: @escaping @MainActor (T) -> Value
    ) -> Preference {
        Preference(key: key, defaultValue: encode(defaultValue),
                   read: { encode($0[keyPath: path]) }, isValid: { decode($0) != nil },
                   write: { value, store in
                       guard let decoded = decode(value) else { return }
                       store[keyPath: path] = decoded
                   })
    }

    private static func boolean(
        _ key: String, _ path: ReferenceWritableKeyPath<SettingsStore, Bool>, default defaultValue: Bool
    ) -> Preference {
        mapped(key, path, default: defaultValue, decode: {
            guard case let .bool(value) = $0 else { return nil }
            return value
        }, encode: { .bool($0) })
    }

    private static func optionalBoolean(
        _ key: String, _ path: ReferenceWritableKeyPath<SettingsStore, Bool?>
    ) -> Preference {
        Preference(key: key, defaultValue: .null,
                   read: { store in store[keyPath: path].map { .bool($0) } ?? .null },
                   isValid: { value in
                       switch value { case .null, .bool: true; default: false }
                   }, write: { value, store in
                       switch value {
                       case .null: store[keyPath: path] = nil
                       case .bool(let enabled): store[keyPath: path] = enabled
                       default: break
                       }
                   })
    }

    private static var slotBindingsPreference: Preference {
        let shipped = IconSlotBindingsV1(
            schemaVersion: 1,
            outerRing: .init(primary: .init(pluginID: "builtin.system-battery", presentationID: "ring")),
            center: .init(
                primary: .init(pluginID: "builtin.legacy", presentationID: "center"),
                fallback: .init(pluginID: "builtin.network", presentationID: "center")),
            footer: .init(primary: .init(pluginID: "builtin.system-volume", presentationID: "footer"))
        )
        let defaultJSON = (try? IconSlotBindingsCodec.encode(shipped))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        func decode(_ value: SettingsTransferValue) -> IconSlotBindingsV1? {
            guard case let .string(json) = value,
                  let data = json.data(using: .utf8),
                  let decoded = try? IconSlotBindingsCodec.decode(data) else { return nil }
            return decoded
        }
        return Preference(
            key: "iconSlotBindings",
            defaultValue: .string(defaultJSON),
            read: { store in
                let json = (try? IconSlotBindingsCodec.encode(store.iconSlotBindings))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? defaultJSON
                return .string(json)
            },
            isValid: { decode($0) != nil },
            write: { value, store in
                guard let decoded = decode(value) else { return }
                for slot in IconSlot.allCases {
                    let selection = decoded.selection(for: slot)
                    store.setIconSlotBinding(
                        primary: selection.primary, fallback: selection.fallback, for: slot)
                }
                store.applyIconSlotBindings(decoded)
            }
        )
    }

    private static func enumeration<T: RawRepresentable>(
        _ key: String, _ path: ReferenceWritableKeyPath<SettingsStore, T>, default defaultValue: T,
        allowed: [T]? = nil
    ) -> Preference where T.RawValue == String {
        mapped(key, path, default: defaultValue, decode: {
            guard case let .string(raw) = $0 else { return nil }
            if let allowed, !allowed.contains(where: { $0.rawValue == raw }) { return nil }
            return T(rawValue: raw)
        }, encode: { .string($0.rawValue) })
    }

    private static func number(
        _ key: String, _ path: ReferenceWritableKeyPath<SettingsStore, Double>, default defaultValue: Double,
        range: ClosedRange<Double>, step: Double? = nil
    ) -> Preference {
        mapped(key, path, default: defaultValue, decode: {
            guard case let .number(value) = $0, value.isFinite, range.contains(value) else { return nil }
            if let step, (value / step).rounded() != value / step { return nil }
            return value
        }, encode: { .number($0) })
    }

    private static func integer(
        _ key: String, _ path: ReferenceWritableKeyPath<SettingsStore, Int>, default defaultValue: Int,
        range: ClosedRange<Int>
    ) -> Preference {
        mapped(key, path, default: defaultValue, decode: {
            guard case let .number(value) = $0, value.isFinite,
                  (Double(range.lowerBound)...Double(range.upperBound)).contains(value),
                  value.rounded() == value else { return nil }
            return Int(value)
        }, encode: { .number(Double($0)) })
    }

    private static var bluetoothColorPreference: Preference {
        mapped("bluetoothIconColor", \.bluetoothIconColor, default: .default, decode: { value in
            guard case let .string(raw) = value,
                  raw == "blue" || raw == "primary" || validCustomColor(raw) else { return nil }
            return BluetoothIconColorSelection(storageValue: raw)
        }, encode: { .string($0.storageValue) })
    }

    private static var panelLevelSliderColorPreference: Preference {
        func decode(_ value: Value) -> PanelLevelSliderColorSelection? {
            guard case let .string(raw) = value,
                  raw == "automatic" || validSliderColor(raw) else { return nil }
            return PanelLevelSliderColorSelection(storageValue: raw)
        }
        func encode(_ selection: PanelLevelSliderColorSelection) -> Value {
            .string(selection.storageValue)
        }
        return Preference(
            key: "panelLevelSliderColor",
            defaultValue: encode(.default),
            read: { encode($0.panelLevelSliderColor) },
            isValid: { decode($0) != nil },
            write: { value, store in
                guard let selection = decode(value) else { return }
                store.panelLevelSliderColor = selection
            }
        )
    }

    private static var batteryColorsPreference: Preference {
        Preference(key: "batteryStatusColors", defaultValue: batteryColorValues(.standard),
                   read: { batteryColorValues($0.batteryStatusColors) },
                   isValid: { value in
                       guard case let .object(roles) = value else { return false }
                       return prepareBatteryColors(roles).warnings.isEmpty
                   }, write: { value, store in
                       guard case let .object(roles) = value else { return }
                       var colors = store.batteryStatusColors
                       for (key, value) in roles {
                           guard let role = BatteryStatusColorRole(rawValue: key),
                                 case let .string(raw) = value, validBatteryColor(raw) else { continue }
                           colors.setSelection(BatteryStatusColorSelection(storageValue: raw), for: role)
                       }
                       if colors != store.batteryStatusColors {
                           store.batteryStatusColors = colors
                       }
                   })
    }

    private static func batteryColorValues(_ colors: BatteryStatusColors) -> Value {
        .object(Dictionary(uniqueKeysWithValues: BatteryStatusColorRole.allCases.map {
            ($0.rawValue, .string(colors.selection(for: $0).storageValue))
        }))
    }

    /// A color object may be sparse just like the top-level preferences. Invalid
    /// roles reset only that role, and absent roles preserve the current palette.
    private static func prepareBatteryColors(_ roles: [String: Value]) -> (values: [String: Value], warnings: [String]) {
        var result: [String: Value] = [:]
        var warnings: [String] = []
        for key in roles.keys.sorted() {
            guard BatteryStatusColorRole(rawValue: key) != nil else {
                warnings.append("Unknown preference: batteryStatusColors.\(key)")
                continue
            }
            if case let .string(raw) = roles[key], validBatteryColor(raw) {
                result[key] = .string(raw)
            } else {
                result[key] = .string("system")
                warnings.append("Invalid preference; using default: batteryStatusColors.\(key)")
            }
        }
        return (result, warnings)
    }

    private static func validBatteryColor(_ raw: String) -> Bool {
        if raw == "system" { return true }
        if raw.hasPrefix("preset:") {
            return BatteryStatusColorPreset(rawValue: String(raw.dropFirst("preset:".count))) != nil
        }
        return validCustomColor(raw)
    }

    private static func validCustomColor(_ raw: String) -> Bool {
        guard raw.hasPrefix("custom:") else { return false }
        let parts = raw.dropFirst("custom:".count).split(separator: ",", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy { part in
            guard let value = Double(part), value.isFinite else { return false }
            return (0...1).contains(value)
        }
    }

    /// Slider fill colour: `automatic` or `custom:r,g,b,a` with every component
    /// in 0...1.
    private static func validSliderColor(_ raw: String) -> Bool {
        guard raw.hasPrefix("custom:") else { return false }
        let parts = raw.dropFirst("custom:".count).split(separator: ",", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            guard let value = Double(part), value.isFinite else { return false }
            return (0...1).contains(value)
        }
    }

    private static func sections(_ value: Value, requiresFullOrder: Bool) -> [PopupSection]? {
        guard case let .array(elements) = value else { return nil }
        var result: [PopupSection] = []
        var seen: Set<PopupSection> = []
        for element in elements {
            guard case let .string(raw) = element, let section = PopupSection(rawValue: raw),
                  seen.insert(section).inserted else { return nil }
            result.append(section)
        }
        if requiresFullOrder, seen != Set(PopupSection.allCases) { return nil }
        return result
    }

    private static func sectionValues(_ sections: [PopupSection]) -> Value {
        .array(sections.map { .string($0.rawValue) })
    }

    private static var popupOrderPreference: Preference {
        Preference(key: "popupSectionOrder", defaultValue: sectionValues(SettingsStore.defaultPopupSectionOrder),
                   read: { sectionValues($0.popupSectionOrder) },
                   isValid: { sections($0, requiresFullOrder: true) != nil },
                   write: { value, store in
                       guard let order = sections(value, requiresFullOrder: true) else { return }
                       for (destination, section) in order.enumerated() {
                           guard let source = store.popupSectionOrder.firstIndex(of: section), source != destination else { continue }
                           store.movePopupSections(fromOffsets: IndexSet(integer: source), toOffset: destination)
                       }
                   })
    }

    private static var enabledSectionsPreference: Preference {
        Preference(key: "enabledPopupSections",
                   defaultValue: sectionValues(SettingsStore.defaultEnabledPopupSections.sorted { $0.rawValue < $1.rawValue }),
                   read: { sectionValues($0.enabledPopupSections.sorted { $0.rawValue < $1.rawValue }) },
                   isValid: { sections($0, requiresFullOrder: false) != nil },
                   write: { value, store in
                       guard let selected = sections(value, requiresFullOrder: false) else { return }
                       let enabled = Set(selected)
                       for section in PopupSection.allCases {
                           store.setPopupSection(section, enabled: enabled.contains(section))
                       }
                   })
    }

    /// Per-ring visibility for the status-panel summary, exported so a transfer
    /// keeps the user's chosen subset. An empty set is invalid on import.
    private static var enabledHardwareRingSlotsPreference: Preference {
        Preference(
            key: "enabledHardwareRingSlots",
            defaultValue: .array(HardwareRingSlot.allCases.map { $0.rawValue }.sorted().map { .string($0) }),
            read: { store in
                .array(store.enabledHardwareRingSlots.map { $0.rawValue }.sorted().map { .string($0) })
            },
            isValid: { value in
                guard case let .array(items) = value, !items.isEmpty else { return false }
                return items.allSatisfy { item in
                    guard case let .string(raw) = item else { return false }
                    return HardwareRingSlot(rawValue: raw) != nil
                }
            },
            write: { value, store in
                guard case let .array(items) = value else { return }
                let slots = Set(items.compactMap { item -> HardwareRingSlot? in
                    guard case let .string(raw) = item else { return nil }
                    return HardwareRingSlot(rawValue: raw)
                })
                store.setEnabledHardwareRingSlots(slots)
            })
    }

    /// Per-info-bar-metric visibility for the status-panel summary.
    private static var enabledHardwareSummaryMetricsPreference: Preference {
        Preference(
            key: "enabledHardwareSummaryMetrics",
            defaultValue: .array(HardwareSummaryMetric.allCases.map { $0.rawValue }.sorted().map { .string($0) }),
            read: { store in
                .array(store.enabledHardwareSummaryMetrics.map { $0.rawValue }.sorted().map { .string($0) })
            },
            isValid: { value in
                guard case let .array(items) = value, !items.isEmpty else { return false }
                return items.allSatisfy { item in
                    guard case let .string(raw) = item else { return false }
                    return HardwareSummaryMetric(rawValue: raw) != nil
                }
            },
            write: { value, store in
                guard case let .array(items) = value else { return }
                let metrics = Set(items.compactMap { item -> HardwareSummaryMetric? in
                    guard case let .string(raw) = item else { return nil }
                    return HardwareSummaryMetric(rawValue: raw)
                })
                store.setEnabledHardwareSummaryMetrics(metrics)
            })
    }
}
