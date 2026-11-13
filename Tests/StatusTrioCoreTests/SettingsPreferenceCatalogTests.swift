import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class SettingsPreferenceCatalogTests: XCTestCase {
    func testSnapshotUsesAnExplicitPortableAllowlist() {
        withStore { store, defaults in
            defaults.set("private-value", forKey: "unrecognizedFutureSetting")
            let snapshot = SettingsPreferenceCatalog.snapshot(store)
            let expected: Set<String> = [
                "appIconPlacement", "dockIconBackgroundPreference", "panelBackgroundStyle",
                "menuBarRightClickAction", "iconSize", "batteryOnBatteryMarker",
                "batteryChargingMarker", "batteryConnectedMarker", "batteryNoBatteryMarker",
                "showsBatteryPowerFlow", "showsBatteryPowerInfoBar", "showsHighEnergyApps",
                "highEnergyAppsRefreshIntervalSeconds", "showsChargeToFullNowButton",
                "showsMenuBarChargingEffect", "showsDockChargingEffect", "showsChargingBoltHeartbeat",
                "batterySplitGapProgress", "usesBatteryStatusColors", "monochromeChargingRing",
                "batteryStatusColors", "batterySymbolScale", "batteryCriticalThreshold",
                "autoLowPowerThreshold", "batteryFullThreshold",
                "showsWiFiIconForEthernet", "showsWiFiIconForHotspot",
                "showsWiFiIconForTemporaryConnection", "showsWiFiIconForInternetSharing",
                "showsLocalIPAddress", "showsSpatialAudioControls", "showsConversationAwarenessControls",
                "connectionCenterSource", "inputSourceMarkerStyle", "prioritizesNetworkErrors",
                "bluetoothIconColor", "usesBluetoothAudioVolumeColor", "showsBluetoothBatteryLevels",
                "showsWiFiPowerControl", "confirmsWiFiPowerOff", "showsBluetoothPowerControl",
                "autoEnablesLowPowerMode", "showsAppleDevicesAndBattery",
                "refreshesAppleBatteriesInBackground", "appleBatteryRefreshIntervalMinutes",
                "showsBluetoothListeningMode", "bluetoothAudioIconChoiceRawValue", "wifiSymbolScale",
                "volumeDisplayStyle", "ringStrokeStyle", "refreshIntervalOnBatterySeconds",
                "refreshIntervalOnPowerSeconds", "maxVisibleOutputDevices", "alwaysShowsAllOutputDevices",
                "maxVisibleInputDevices", "alwaysShowsAllInputDevices", "showsBluetoothDeviceList",
                "maxVisibleBluetoothDevices", "hidesGhostBluetoothDevices", "popupSectionOrder",
                "enabledPopupSections", "popupPanelScrollAdjustsVolume", "returnsToSummaryOnOpen",
                "popupVolumeNaturalScrolling", "popupVolumeScrollFeedbackOverride", "popupScrollWheelStepPercent"
            ]
            XCTAssertEqual(Set(snapshot.keys), expected)
        }
    }

    func testRoundTripIncludesBothIconSurfacesAndPersistsThroughStoreSetters() {
        withStore { source, _ in
            source.iconSize = 31
            source.showsMenuBarChargingEffect = false
            source.showsDockChargingEffect = true
            source.monochromeChargingRing = false
            source.popupScrollWheelStepPercent = 2.5
            source.popupVolumeScrollFeedbackOverride = true
            source.batteryStatusColors.charging = .custom(.init(hue: 0.2, saturation: 0.6, brightness: 0.8))
            source.bluetoothIconColor = .custom(.init(hue: 0.1, saturation: 0.4, brightness: 0.9))
            source.bluetoothAudioIconChoice = .airpods
            source.setPopupSection(.brightness, enabled: true)
            source.movePopupSections(fromOffsets: IndexSet(integer: 7), toOffset: 0)
            let snapshot = SettingsPreferenceCatalog.snapshot(source)
            let prepared = SettingsPreferenceCatalog.prepare(snapshot)
            XCTAssertTrue(prepared.warnings.isEmpty)
            XCTAssertEqual(prepared.values, snapshot)
            withStore { target, defaults in
                SettingsPreferenceCatalog.apply(prepared.values, to: target)
                XCTAssertEqual(SettingsPreferenceCatalog.snapshot(target), snapshot)
                let reloaded = SettingsStore(defaults: defaults, systemChargeLimit: { nil })
                XCTAssertEqual(SettingsPreferenceCatalog.snapshot(reloaded), snapshot)
            }
        }
    }

    func testWheelStepValidatesRangeAndPersistsDefaultAndCustomValues() {
        withStore { store, defaults in
            XCTAssertEqual(store.popupScrollWheelStepPercent, 5)
            for value in [1.0, 2.5, 5, 20] {
                store.popupScrollWheelStepPercent = value
                XCTAssertEqual(SettingsStore(defaults: defaults).popupScrollWheelStepPercent, value)
            }
            for value in [0.0, 21, 2.7, .infinity, .nan] {
                store.popupScrollWheelStepPercent = value
                XCTAssertEqual(store.popupScrollWheelStepPercent, 5)
                XCTAssertEqual(defaults.double(forKey: "popupScrollWheelStepPercent"), 5)
            }
            for value in [-1.0, 21, 2.7] {
                let prepared = SettingsPreferenceCatalog.prepare(["popupScrollWheelStepPercent": .number(value)])
                XCTAssertEqual(prepared.values["popupScrollWheelStepPercent"], .number(5))
                XCTAssertFalse(prepared.warnings.isEmpty)
            }
        }
    }

    func testSparseApplyPreservesUnspecifiedPreferencesAndPrivateState() {
        withStore { store, _ in
            store.iconSize = 33
            store.showsDockChargingEffect = false
            store.setSharesAnonymousAnalytics(true)
            store.hasCompletedIconGuideOnboarding = true
            let before = SettingsPreferenceCatalog.snapshot(store)
            SettingsPreferenceCatalog.apply(["showsMenuBarChargingEffect": .bool(false)], to: store)
            var expected = before
            expected["showsMenuBarChargingEffect"] = .bool(false)
            XCTAssertEqual(SettingsPreferenceCatalog.snapshot(store), expected)
            XCTAssertTrue(store.sharesAnonymousAnalytics)
            XCTAssertTrue(store.hasCompletedIconGuideOnboarding)
        }
    }

    func testApplyingPreferencesSupersedesPendingSliderWrites() {
        withStore { store, defaults in
            store.setIconSizeFromSlider(36)
            store.setBatterySymbolScaleFromSlider(1.1)
            store.setWiFiSymbolScaleFromSlider(1.8)
            SettingsPreferenceCatalog.apply([
                "iconSize": .number(19.5), "batterySymbolScale": .number(0.95), "wifiSymbolScale": .number(1.3)
            ], to: store)
            store.flushPendingPersists()
            XCTAssertEqual(defaults.double(forKey: SettingsStore.iconSizeDefaultsKey), 19.5)
            XCTAssertEqual(defaults.double(forKey: SettingsStore.batterySymbolScaleDefaultsKey), 0.95)
            XCTAssertEqual(defaults.double(forKey: SettingsStore.wifiSymbolScaleDefaultsKey), 1.3)
        }
    }

    func testInvalidTypesAndUnknownKeysCannotGrantConsentOrChangeDeviceIdentity() {
        let excluded = [
            "sharesAnonymousAnalytics", "telemetryConsentVersion", "statusPanelShortcut", "controlsLowPowerMode",
            "hasCompletedIconGuideOnboarding", "simulatesNoBattery", "testsChargingEffect",
            "previewsBluetoothListeningMode", "bluetoothListeningModePreviewDeviceName",
            "bluetoothListeningModePreviewDeviceCount", "bluetoothListeningModePreviewLanguage",
            "nearbyBLESelections", "trustedAppleDeviceMetadata", "nearbyBLEConsent.v1",
            "appleDeviceSelections", "archivedLegacyNearbyBLESelections", "outputDeviceOrder",
            "hiddenOutputDeviceUIDs", "inputDeviceOrder", "hiddenInputDeviceUIDs",
            "externalVolumeConfigurations", "externalBrightnessConfigurations", "hiddenBrightnessDisplayIDs",
            "bluetoothDeviceOrder", "hiddenBluetoothDeviceAddresses", "revealedGhostBluetoothDeviceAddresses",
            "bluetoothNetworkIconDeviceAddress", "bluetoothNetworkIconSymbolName",
            "showsNearbyBluetoothBatteryDevices", "showsMobileDeviceBatteryLevels",
            "refreshIntervalSeconds", "bluetoothSymbolScale", "showsChargingEffect",
            "popupVolumeScrollDirection", "chargeToFullRestoreLimit",
            "showsBatteryPercentage", "showsChargingIndicator", "batteryConnectedIndicator"
        ]
        let prepared = SettingsPreferenceCatalog.prepare(Dictionary(uniqueKeysWithValues: excluded.map { ($0, .bool(true)) }))
        XCTAssertTrue(prepared.values.isEmpty)
        XCTAssertEqual(prepared.warnings.count, excluded.count)
        withStore { store, _ in
            SettingsPreferenceCatalog.apply(prepared.values, to: store)
            XCTAssertFalse(store.sharesAnonymousAnalytics)
            XCTAssertTrue(store.outputDeviceOrder.isEmpty)
            XCTAssertTrue(store.trustedAppleDeviceMetadata.isEmpty)
        }
    }

    func testGhostBluetoothFilterTransfersItsSavedBehaviorAndPersists() {
        withStore { store, defaults in
            XCTAssertEqual(SettingsPreferenceCatalog.snapshot(store)["hidesGhostBluetoothDevices"], .bool(true))
            for hidesGhosts in [false, true] {
                let values: [String: SettingsTransferValue] = ["hidesGhostBluetoothDevices": .bool(hidesGhosts)]
                let prepared = SettingsPreferenceCatalog.prepare(values)
                XCTAssertEqual(prepared.values, values)
                XCTAssertTrue(prepared.warnings.isEmpty)
                SettingsPreferenceCatalog.apply(prepared.values, to: store)
                XCTAssertEqual(SettingsPreferenceCatalog.snapshot(store)["hidesGhostBluetoothDevices"], .bool(hidesGhosts))
                XCTAssertEqual(store.bluetoothDeviceListOptions.hidesGhostDevices, hidesGhosts)
                let reloaded = SettingsStore(defaults: defaults, systemChargeLimit: { nil })
                XCTAssertEqual(reloaded.bluetoothDeviceListOptions.hidesGhostDevices, hidesGhosts)
            }
        }
    }

    func testHelperOptInRemainsLocalWhileAutomationPreferencesTransfer() {
        for localOptIn in [false, true] {
            withStore { store, defaults in
                store.controlsLowPowerMode = localOptIn
                XCTAssertNil(SettingsPreferenceCatalog.snapshot(store)["controlsLowPowerMode"])
                let incoming: [String: SettingsTransferValue] = [
                    "controlsLowPowerMode": .bool(!localOptIn),
                    "autoEnablesLowPowerMode": .bool(true), "autoLowPowerThreshold": .number(37)
                ]
                let prepared = SettingsPreferenceCatalog.prepare(incoming)
                XCTAssertNil(prepared.values["controlsLowPowerMode"])
                XCTAssertEqual(prepared.warnings.count, 1)
                SettingsPreferenceCatalog.apply(incoming, to: store)
                XCTAssertEqual(store.controlsLowPowerMode, localOptIn)
                XCTAssertEqual(defaults.bool(forKey: SettingsStore.controlsLowPowerModeDefaultsKey), localOptIn)
                XCTAssertTrue(store.autoEnablesLowPowerMode)
                XCTAssertEqual(store.autoLowPowerThreshold, 37)
            }
        }
    }

    func testInvalidKnownValuesFallBackToShippedDefaultsWithoutChangingStore() {
        withStore { store, _ in
            let shipped = SettingsPreferenceCatalog.snapshot(store)
            store.iconSize = 34
            let invalid = Dictionary(uniqueKeysWithValues: shipped.keys.map { ($0, SettingsTransferValue.string("invalid")) })
            let result = SettingsPreferenceCatalog.prepare(invalid)
            XCTAssertEqual(result.values, shipped)
            XCTAssertEqual(result.warnings.count, shipped.count)
            XCTAssertEqual(store.iconSize, 34)
        }
    }

    func testNumbersMustBeFiniteInRangeAndRespectShippedSteps() {
        let invalid: [String: SettingsTransferValue] = [
            "iconSize": .number(.infinity), "wifiSymbolScale": .number(.nan),
            "batterySymbolScale": .number(0.8), "batteryCriticalThreshold": .number(20.5),
            "autoLowPowerThreshold": .number(-1), "batteryFullThreshold": .number(49),
            "highEnergyAppsRefreshIntervalSeconds": .number(11),
            "refreshIntervalOnBatterySeconds": .number(5.5), "refreshIntervalOnPowerSeconds": .number(61),
            "maxVisibleOutputDevices": .number(1.5), "maxVisibleInputDevices": .number(21),
            "maxVisibleBluetoothDevices": .number(0), "appleBatteryRefreshIntervalMinutes": .bool(true)
        ]
        withStore { store, _ in
            let defaults = SettingsPreferenceCatalog.snapshot(store)
            let result = SettingsPreferenceCatalog.prepare(invalid)
            XCTAssertEqual(result.warnings.count, invalid.count)
            for key in invalid.keys { XCTAssertEqual(result.values[key], defaults[key], key) }
        }
        let valid: [String: SettingsTransferValue] = [
            "iconSize": .number(16.5), "wifiSymbolScale": .number(1.8),
            "batteryCriticalThreshold": .number(0), "autoLowPowerThreshold": .number(100),
            "batteryFullThreshold": .number(50),
            "highEnergyAppsRefreshIntervalSeconds": .number(60), "refreshIntervalOnBatterySeconds": .number(7),
            "maxVisibleOutputDevices": .number(20), "appleBatteryRefreshIntervalMinutes": .number(10)
        ]
        XCTAssertEqual(SettingsPreferenceCatalog.prepare(valid).values, valid)
        XCTAssertTrue(SettingsPreferenceCatalog.prepare(valid).warnings.isEmpty)
    }

    func testStrictBooleansEnumsAndNullableOverrides() {
        let values: [String: SettingsTransferValue] = [
            "showsMenuBarChargingEffect": .number(0), "appIconPlacement": .string("invented"),
            "batteryOnBatteryMarker": .string("invented"), "bluetoothAudioIconChoiceRawValue": .string("private-symbol"),
            "popupVolumeScrollFeedbackOverride": .string("true"), "monochromeChargingRing": .number(1)
        ]
        let result = SettingsPreferenceCatalog.prepare(values)
        XCTAssertEqual(result.warnings.count, values.count)
        XCTAssertEqual(result.values["showsMenuBarChargingEffect"], .bool(true))
        XCTAssertEqual(result.values["appIconPlacement"], .string("menuBar"))
        XCTAssertEqual(result.values["batteryOnBatteryMarker"], .string("percentage"))
        XCTAssertEqual(result.values["bluetoothAudioIconChoiceRawValue"], .string("automatic"))
        XCTAssertEqual(result.values["popupVolumeScrollFeedbackOverride"], .null)
        XCTAssertEqual(result.values["monochromeChargingRing"], .null)
        withStore { store, _ in
            store.monochromeChargingRing = true
            store.popupVolumeScrollFeedbackOverride = false
            SettingsPreferenceCatalog.apply(["monochromeChargingRing": .null, "popupVolumeScrollFeedbackOverride": .null], to: store)
            XCTAssertNil(store.monochromeChargingRing)
            XCTAssertNil(store.popupVolumeScrollFeedbackOverride)
        }
    }

    func testBatteryMarkersRespectStateSpecificOptions() {
        let invalid: [String: SettingsTransferValue] = [
            "batteryOnBatteryMarker": .string("bolt"), "batteryNoBatteryMarker": .string("percentage")
        ]
        let prepared = SettingsPreferenceCatalog.prepare(invalid)
        XCTAssertEqual(prepared.warnings.count, 2)
        XCTAssertEqual(prepared.values["batteryOnBatteryMarker"], .string("percentage"))
        XCTAssertEqual(prepared.values["batteryNoBatteryMarker"], .string("plug"))
        for marker in BatteryTopMarker.onPowerOptions {
            let values: [String: SettingsTransferValue] = [
                "batteryChargingMarker": .string(marker.rawValue), "batteryConnectedMarker": .string(marker.rawValue)
            ]
            XCTAssertTrue(SettingsPreferenceCatalog.prepare(values).warnings.isEmpty)
        }
    }

    func testSparseColorObjectPreservesMissingRolesAndWarnsForUnknownRoles() {
        withStore { store, _ in
            store.batteryStatusColors.lowPower = .preset(.mint)
            store.batteryStatusColors.highPower = .preset(.sky)
            store.batteryStatusColors.critical = .preset(.rose)
            let prepared = SettingsPreferenceCatalog.prepare([
                "batteryStatusColors": .object(["charging": .string("preset:amber"), "futureRole": .bool(true)])
            ])
            XCTAssertEqual(prepared.warnings.count, 1)
            XCTAssertEqual(prepared.values["batteryStatusColors"], .object(["charging": .string("preset:amber")]))
            SettingsPreferenceCatalog.apply(prepared.values, to: store)
            XCTAssertEqual(store.batteryStatusColors, BatteryStatusColors(
                charging: .preset(.amber), lowPower: .preset(.mint), highPower: .preset(.sky), critical: .preset(.rose)
            ))
            let invalid = SettingsPreferenceCatalog.prepare(["batteryStatusColors": .object(["charging": .bool(true)])])
            XCTAssertEqual(invalid.warnings.count, 1)
            SettingsPreferenceCatalog.apply(invalid.values, to: store)
            XCTAssertEqual(store.batteryStatusColors.charging, .system)
            XCTAssertEqual(store.batteryStatusColors.lowPower, .preset(.mint))
            let before = store.batteryStatusColors
            SettingsPreferenceCatalog.apply(["batteryStatusColors": .object([:])], to: store)
            XCTAssertEqual(store.batteryStatusColors, before)
        }
    }

    func testColorsRejectClampingNonFiniteAndMalformedComponents() {
        for invalid in ["custom:-0.1,0.2,0.3", "custom:0.1,1.1,0.3", "custom:nan,0.2,0.3", "custom:inf,0.2,0.3", "custom:0.1,,0.3", "custom:0.1,0.2,0.3,", "preset:invented", "unknown"] {
            let result = SettingsPreferenceCatalog.prepare(["bluetoothIconColor": .string(invalid)])
            XCTAssertEqual(result.values["bluetoothIconColor"], .string("blue"), invalid)
            XCTAssertEqual(result.warnings.count, 1, invalid)
        }
        let valid: [String: SettingsTransferValue] = [
            "bluetoothIconColor": .string("custom:0.0,0.4,1.0"),
            "batteryStatusColors": .object([
                "charging": .string("custom:0.0,0.4,1.0"), "lowPower": .string("system"),
                "highPower": .string("preset:sky"), "critical": .string("preset:rose")
            ])
        ]
        XCTAssertEqual(SettingsPreferenceCatalog.prepare(valid).values, valid)
        XCTAssertTrue(SettingsPreferenceCatalog.prepare(valid).warnings.isEmpty)
        let malformed: SettingsTransferValue = .object([
            "charging": .string("custom:0.2,0.3,2"), "lowPower": .string("system"),
            "highPower": .string("system"), "critical": .string("system")
        ])
        let result = SettingsPreferenceCatalog.prepare(["batteryStatusColors": malformed])
        XCTAssertEqual(result.warnings.count, 1)
        withStore { store, _ in
            XCTAssertEqual(result.values["batteryStatusColors"], SettingsPreferenceCatalog.snapshot(store)["batteryStatusColors"])
        }
    }

    func testPanelArraysRejectDuplicatesUnknownElementsAndIncompleteOrder() {
        for invalid: SettingsTransferValue in [.array([.string("battery"), .string("battery")]), .array([.string("unknown")]), .array([.bool(true)])] {
            let result = SettingsPreferenceCatalog.prepare(["enabledPopupSections": invalid])
            XCTAssertEqual(result.warnings.count, 1)
        }
        XCTAssertEqual(SettingsPreferenceCatalog.prepare(["popupSectionOrder": .array([.string("battery")])]).warnings.count, 1)
        let empty: [String: SettingsTransferValue] = ["enabledPopupSections": .array([])]
        XCTAssertTrue(SettingsPreferenceCatalog.prepare(empty).warnings.isEmpty)
        withStore { store, _ in
            SettingsPreferenceCatalog.apply(empty, to: store)
            XCTAssertTrue(store.enabledPopupSections.isEmpty)
        }
    }

    func testPanelOrderAppliesACompletePermutationThroughExistingMethods() {
        withStore { store, _ in
            let reversed = Array(SettingsStore.defaultPopupSectionOrder.reversed())
            SettingsPreferenceCatalog.apply([
                "popupSectionOrder": .array(reversed.map { .string($0.rawValue) })
            ], to: store)
            XCTAssertEqual(store.popupSectionOrder, reversed)
            XCTAssertEqual(store.enabledPopupSections, SettingsStore.defaultEnabledPopupSections)
        }
    }

    private func withStore(_ body: (SettingsStore, UserDefaults) -> Void) {
        let name = "SettingsPreferenceCatalogTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults, systemChargeLimit: { nil })
        body(store, defaults)
        store.flushPendingPersists()
    }
}
