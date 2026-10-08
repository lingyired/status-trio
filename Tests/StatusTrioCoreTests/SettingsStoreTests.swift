import AppKit
import Combine
import CoreAudio
import XCTest
@testable import StatusTrioCore

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testDefaultsMatchSpecifiedRange() {
        XCTAssertEqual(SettingsStore.iconSizeRange, 16...36)

        let store = SettingsStore(defaults: makeSuite().defaults)
        XCTAssertEqual(store.iconSize, 24, accuracy: 0.001)
    }

    func testConnectedPowerPercentageDefaultsOffAndFeedsTheIconOptions() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        XCTAssertFalse(store.showsPercentageWhenConnected)
        XCTAssertFalse(store.batteryIconOptions.showsPercentageWhenConnected)
    }

    func testConnectedPowerPercentageChoicePersists() {
        let suite = makeSuite()
        defer { clear(suite) }

        let first = SettingsStore(defaults: suite.defaults)
        first.showsPercentageWhenConnected = true

        let second = SettingsStore(defaults: suite.defaults)
        XCTAssertTrue(second.showsPercentageWhenConnected)
        XCTAssertTrue(second.batteryIconOptions.showsPercentageWhenConnected)
    }

    func testRefreshIntervalDefaultsAndRange() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        XCTAssertEqual(SettingsStore.refreshIntervalRange, 5...60)
        XCTAssertEqual(store.refreshIntervalSeconds, 15, accuracy: 0.001)
        XCTAssertEqual(store.refreshInterval, .seconds(15))
    }

    func testRefreshIntervalClampsRoundsAndPersists() {
        let suite = makeSuite()
        defer { clear(suite) }

        let first = SettingsStore(defaults: suite.defaults)
        first.refreshIntervalSeconds = 7
        XCTAssertEqual(first.refreshIntervalSeconds, 5, accuracy: 0.001)

        first.refreshIntervalSeconds = 307
        XCTAssertEqual(first.refreshIntervalSeconds, 60, accuracy: 0.001)

        first.refreshIntervalSeconds = 32
        XCTAssertEqual(first.refreshIntervalSeconds, 30, accuracy: 0.001)

        let second = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(second.refreshIntervalSeconds, 30, accuracy: 0.001)
    }

    func testBatteryDisplayDefaults() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        XCTAssertTrue(store.showsBatteryPercentage)
        XCTAssertTrue(store.showsChargingIndicator)
        XCTAssertTrue(store.usesBatteryStatusColors)
        XCTAssertEqual(store.batteryCriticalThreshold, 20, accuracy: 0.001)
        XCTAssertEqual(store.batterySymbolScale, 1, accuracy: 0.001)
        XCTAssertEqual(store.batteryIconOptions, .standard)
    }

    func testBatteryDisplaySettingsPersistAcrossStoreInstances() {
        let suite = makeSuite()
        defer { clear(suite) }

        let first = SettingsStore(defaults: suite.defaults)
        first.showsBatteryPercentage = false
        first.showsChargingIndicator = false
        first.usesBatteryStatusColors = false
        first.batteryCriticalThreshold = 35
        first.batterySymbolScale = 0.95

        let second = SettingsStore(defaults: suite.defaults)
        XCTAssertFalse(second.showsBatteryPercentage)
        XCTAssertFalse(second.showsChargingIndicator)
        XCTAssertFalse(second.usesBatteryStatusColors)
        XCTAssertEqual(second.batteryCriticalThreshold, 35, accuracy: 0.001)
        XCTAssertEqual(second.batterySymbolScale, 0.95, accuracy: 0.001)
    }

    func testAppleBackgroundRefreshDefaultsOffAndIntervalDefaultsToOneMinute() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        XCTAssertFalse(store.refreshesAppleBatteriesInBackground)
        XCTAssertEqual(store.appleBatteryRefreshIntervalMinutes, 1)
    }

    func testAppleBackgroundRefreshIntervalClampsAndPersistsWhenToggleTurnsOff() {
        let suite = makeSuite()
        defer { clear(suite) }

        let first = SettingsStore(defaults: suite.defaults)
        first.appleBatteryRefreshIntervalMinutes = 0
        XCTAssertEqual(first.appleBatteryRefreshIntervalMinutes, 1)

        first.appleBatteryRefreshIntervalMinutes = 11
        XCTAssertEqual(first.appleBatteryRefreshIntervalMinutes, 10)

        first.appleBatteryRefreshIntervalMinutes = 6
        first.refreshesAppleBatteriesInBackground = true
        first.refreshesAppleBatteriesInBackground = false

        let second = SettingsStore(defaults: suite.defaults)
        XCTAssertFalse(second.refreshesAppleBatteriesInBackground)
        XCTAssertEqual(second.appleBatteryRefreshIntervalMinutes, 6)
        second.refreshesAppleBatteriesInBackground = true
        XCTAssertEqual(second.appleBatteryRefreshIntervalMinutes, 6)
    }

    func testStoredAppleBackgroundIntervalClampsToSupportedBoundsAndInvalidDefaults() {
        let low = makeSuite()
        defer { clear(low) }
        low.defaults.set(0, forKey: SettingsStore.appleBatteryRefreshIntervalMinutesDefaultsKey)
        XCTAssertEqual(SettingsStore(defaults: low.defaults).appleBatteryRefreshIntervalMinutes, 1)

        let high = makeSuite()
        defer { clear(high) }
        high.defaults.set(20, forKey: SettingsStore.appleBatteryRefreshIntervalMinutesDefaultsKey)
        XCTAssertEqual(SettingsStore(defaults: high.defaults).appleBatteryRefreshIntervalMinutes, 10)

        let invalid = makeSuite()
        defer { clear(invalid) }
        invalid.defaults.set("bad", forKey: SettingsStore.appleBatteryRefreshIntervalMinutesDefaultsKey)
        XCTAssertEqual(SettingsStore(defaults: invalid.defaults).appleBatteryRefreshIntervalMinutes, 1)
    }

    func testConnectionIconDisplayDefaults() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        XCTAssertFalse(store.showsWiFiIconForEthernet)
        XCTAssertFalse(store.showsWiFiIconForHotspot)
        XCTAssertFalse(store.showsWiFiIconForTemporaryConnection)
        XCTAssertFalse(store.showsWiFiIconForInternetSharing)
        XCTAssertEqual(
            store.connectionIconOptions,
            ConnectionIconOptions(wifiScale: SettingsStore.defaultWifiSymbolScale)
        )
    }

    func testConnectionIconDisplaySettingsPersistAcrossStoreInstances() {
        let suite = makeSuite()
        defer { clear(suite) }

        let first = SettingsStore(defaults: suite.defaults)
        first.showsWiFiIconForEthernet = true
        first.showsWiFiIconForHotspot = true
        first.showsWiFiIconForTemporaryConnection = true
        first.showsWiFiIconForInternetSharing = true

        let second = SettingsStore(defaults: suite.defaults)
        XCTAssertTrue(second.showsWiFiIconForEthernet)
        XCTAssertTrue(second.showsWiFiIconForHotspot)
        XCTAssertTrue(second.showsWiFiIconForTemporaryConnection)
        XCTAssertTrue(second.showsWiFiIconForInternetSharing)
    }

    func testBluetoothAudioDisplayDefaults() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        XCTAssertFalse(store.replacesNetworkIconWithBluetoothAudio)
        XCTAssertFalse(store.usesBluetoothAudioVolumeColor)
        XCTAssertTrue(store.prioritizesNetworkErrorsOverBluetoothAudio)
        // Levels are a display-only read: a surface has to claim them, and the
        // claim only exists while a Bluetooth surface is on screen, so the
        // default is on.
        XCTAssertTrue(store.showsBluetoothBatteryLevels)
        XCTAssertEqual(
            store.bluetoothSymbolScale,
            SettingsStore.defaultBluetoothSymbolScale,
            accuracy: 0.001
        )
        XCTAssertEqual(store.bluetoothAudioIconOptions, .standard)
    }

    func testBluetoothNetworkIconDeviceDefaultsToTheAudioDevice() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        XCTAssertNil(store.bluetoothNetworkIconDeviceAddress)
        XCTAssertNil(store.bluetoothNetworkIconSymbolName)
        XCTAssertNil(store.bluetoothAudioIconOptions.networkIconSymbolOverride)
    }

    /// Picking a device stores its address for the picker's highlight and the
    /// symbol the icon draws, as one atomic choice; picking the audio device
    /// again clears both.
    func testBluetoothNetworkIconDeviceChoicePersistsAcrossStoreInstances() {
        let suite = makeSuite()
        defer { clear(suite) }

        let first = SettingsStore(defaults: suite.defaults)
        first.setBluetoothNetworkIconDevice(address: "aa-bb-cc-dd-ee-ff", symbolName: "keyboard")

        let second = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(second.bluetoothNetworkIconDeviceAddress, "aa-bb-cc-dd-ee-ff")
        XCTAssertEqual(second.bluetoothNetworkIconSymbolName, "keyboard")
        XCTAssertEqual(
            second.bluetoothAudioIconOptions.networkIconSymbolOverride,
            "keyboard"
        )

        second.setBluetoothNetworkIconDevice(address: nil, symbolName: nil)
        XCTAssertNil(second.bluetoothNetworkIconDeviceAddress)
        XCTAssertNil(second.bluetoothNetworkIconSymbolName)
        XCTAssertNil(second.bluetoothAudioIconOptions.networkIconSymbolOverride)
    }

    func testNearbyBluetoothBatteryDefaultsOff() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        XCTAssertFalse(store.showsNearbyBluetoothBatteryDevices)
    }

    func testNearbyBluetoothBatteryChoicePersists() {
        let suite = makeSuite()
        defer { clear(suite) }

        let first = SettingsStore(defaults: suite.defaults)
        XCTAssertFalse(first.showsNearbyBluetoothBatteryDevices)
        first.showsNearbyBluetoothBatteryDevices = true

        XCTAssertTrue(SettingsStore(defaults: suite.defaults).showsNearbyBluetoothBatteryDevices)
    }

    func testMobileBatteryDeviceChoiceDefaultsOffAndIsIndependentOfNearbyOptIn() {
        let suite = makeSuite()
        defer { clear(suite) }

        let store = SettingsStore(defaults: suite.defaults)

        XCTAssertFalse(store.showsMobileDeviceBatteryLevels)
        XCTAssertFalse(store.showsNearbyBluetoothBatteryDevices)
        store.showsNearbyBluetoothBatteryDevices = true
        XCTAssertFalse(store.showsMobileDeviceBatteryLevels)
    }

    func testMobileBatteryDeviceChoicePersistsAcrossStoreInstances() {
        let suite = makeSuite()
        defer { clear(suite) }

        let first = SettingsStore(defaults: suite.defaults)
        XCTAssertFalse(first.showsMobileDeviceBatteryLevels)
        first.showsMobileDeviceBatteryLevels = true

        XCTAssertTrue(SettingsStore(defaults: suite.defaults).showsMobileDeviceBatteryLevels)
    }

    func testBluetoothAudioDisplaySettingsPersistAcrossStoreInstances() {
        let suite = makeSuite()
        defer { clear(suite) }

        let first = SettingsStore(defaults: suite.defaults)
        first.replacesNetworkIconWithBluetoothAudio = true
        first.usesBluetoothAudioVolumeColor = true
        first.prioritizesNetworkErrorsOverBluetoothAudio = false
        first.showsBluetoothBatteryLevels = true
        first.bluetoothSymbolScale = 1.45

        let second = SettingsStore(defaults: suite.defaults)
        XCTAssertTrue(second.replacesNetworkIconWithBluetoothAudio)
        XCTAssertTrue(second.usesBluetoothAudioVolumeColor)
        XCTAssertFalse(second.prioritizesNetworkErrorsOverBluetoothAudio)
        XCTAssertTrue(second.showsBluetoothBatteryLevels)
        XCTAssertEqual(second.bluetoothSymbolScale, 1.45, accuracy: 0.001)
        XCTAssertEqual(
            second.bluetoothAudioIconOptions,
            BluetoothAudioIconOptions(
                replacesNetworkIcon: true,
                usesVolumeColor: true,
                prioritizesNetworkErrors: false,
                symbolScale: 1.45
            )
        )
    }

    func testBluetoothAudioDisplayFallsBackToDefaultsForNonBooleanStoredValues() {
        let suite = makeSuite()
        defer { clear(suite) }
        suite.defaults.set(
            "yes",
            forKey: SettingsStore.replacesNetworkIconWithBluetoothAudioDefaultsKey
        )
        suite.defaults.set(
            "yes",
            forKey: SettingsStore.usesBluetoothAudioVolumeColorDefaultsKey
        )
        suite.defaults.set(
            "no",
            forKey: SettingsStore.prioritizesNetworkErrorsOverBluetoothAudioDefaultsKey
        )
        suite.defaults.set(
            "yes",
            forKey: SettingsStore.showsBluetoothBatteryLevelsDefaultsKey
        )

        let store = SettingsStore(defaults: suite.defaults)

        XCTAssertFalse(store.replacesNetworkIconWithBluetoothAudio)
        XCTAssertFalse(store.usesBluetoothAudioVolumeColor)
        XCTAssertTrue(store.prioritizesNetworkErrorsOverBluetoothAudio)
        XCTAssertTrue(store.showsBluetoothBatteryLevels)
    }

    func testWiFiSymbolScaleDefaultsAndClamping() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        XCTAssertEqual(SettingsStore.wifiSymbolScaleRange, 1.0...1.8)
        XCTAssertEqual(store.wifiSymbolScale, 1.6, accuracy: 0.001)

        store.wifiSymbolScale = 2.5
        XCTAssertEqual(store.wifiSymbolScale, 1.8, accuracy: 0.001)

        store.wifiSymbolScale = 0.5
        XCTAssertEqual(store.wifiSymbolScale, 1.0, accuracy: 0.001)
    }

    func testWiFiAndBluetoothSymbolScaleShareTheSameDefaultsAndRange() {
        XCTAssertEqual(
            SettingsStore.wifiSymbolScaleRange,
            SettingsStore.bluetoothSymbolScaleRange
        )
        XCTAssertEqual(
            SettingsStore.defaultWifiSymbolScale,
            SettingsStore.defaultBluetoothSymbolScale,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SettingsStore.statusCenterSymbolScaleRange,
            SettingsStore.wifiSymbolScaleRange
        )
        XCTAssertEqual(
            SettingsStore.defaultStatusCenterSymbolScale,
            SettingsStore.defaultWifiSymbolScale,
            accuracy: 0.001
        )
    }

    func testWiFiSymbolScalePersistsAcrossStoreInstances() {
        let suite = makeSuite()
        defer { clear(suite) }

        let first = SettingsStore(defaults: suite.defaults)
        first.wifiSymbolScale = 1.45

        let second = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(second.wifiSymbolScale, 1.45, accuracy: 0.001)
        XCTAssertEqual(second.connectionIconOptions.wifiScale, 1.45, accuracy: 0.001)
    }

    func testBluetoothSymbolScaleDefaultsAndClamping() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        XCTAssertEqual(SettingsStore.bluetoothSymbolScaleRange, 1.0...1.8)
        XCTAssertEqual(store.bluetoothSymbolScale, 1.6, accuracy: 0.001)

        store.bluetoothSymbolScale = 2.5
        XCTAssertEqual(store.bluetoothSymbolScale, 1.8, accuracy: 0.001)

        store.bluetoothSymbolScale = 0.5
        XCTAssertEqual(store.bluetoothSymbolScale, 1.0, accuracy: 0.001)
    }

    func testBluetoothSymbolScalePersistsAcrossStoreInstances() {
        let suite = makeSuite()
        defer { clear(suite) }

        let first = SettingsStore(defaults: suite.defaults)
        first.bluetoothSymbolScale = 1.45

        let second = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(second.bluetoothSymbolScale, 1.45, accuracy: 0.001)
        XCTAssertEqual(second.bluetoothAudioIconOptions.symbolScale, 1.45, accuracy: 0.001)
    }

    func testVolumeDisplayStyleDefaultsAndPersists() {
        let suite = makeSuite()
        defer { clear(suite) }

        let first = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(first.volumeDisplayStyle, .dots)
        XCTAssertEqual(first.volumeIconOptions.displayStyle, .dots)

        first.volumeDisplayStyle = .arc

        let second = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(second.volumeDisplayStyle, .arc)
        XCTAssertEqual(second.volumeIconOptions.displayStyle, .arc)
    }

    func testBatteryCriticalThresholdIsClamped() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        store.batteryCriticalThreshold = 140
        XCTAssertEqual(store.batteryCriticalThreshold, 100, accuracy: 0.001)

        store.batteryCriticalThreshold = -5
        XCTAssertEqual(store.batteryCriticalThreshold, 0, accuracy: 0.001)
    }

    func testBatterySymbolSizeIsEnabledWhenEitherSymbolIsVisible() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        store.showsBatteryPercentage = true
        store.showsChargingIndicator = false
        XCTAssertTrue(store.isBatterySymbolSizeEnabled)

        store.showsBatteryPercentage = false
        store.showsChargingIndicator = true
        XCTAssertTrue(store.isBatterySymbolSizeEnabled)

        store.showsBatteryPercentage = false
        store.showsChargingIndicator = false
        XCTAssertFalse(store.isBatterySymbolSizeEnabled)
    }

    func testBatterySymbolScaleIsClamped() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        store.batterySymbolScale = 4
        XCTAssertEqual(store.batterySymbolScale, 1.1, accuracy: 0.001)

        store.batterySymbolScale = 0.5
        XCTAssertEqual(store.batterySymbolScale, 0.9, accuracy: 0.001)
    }

    func testStoredBatterySymbolScaleIsClampedOnLoad() {
        let suite = makeSuite()
        defer { clear(suite) }
        suite.defaults.set(4, forKey: SettingsStore.batterySymbolScaleDefaultsKey)

        let store = SettingsStore(defaults: suite.defaults)

        XCTAssertEqual(store.batterySymbolScale, 1.1, accuracy: 0.001)
    }

    func testStoredBatteryCriticalThresholdIsClampedOnLoad() {
        let suite = makeSuite()
        defer { clear(suite) }
        suite.defaults.set(150, forKey: SettingsStore.batteryCriticalThresholdDefaultsKey)

        let store = SettingsStore(defaults: suite.defaults)

        XCTAssertEqual(store.batteryCriticalThreshold, 100, accuracy: 0.001)
    }

    func testIconSizeAboveRangeIsClampedToUpperBound() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        store.iconSize = 120

        XCTAssertEqual(store.iconSize, 36, accuracy: 0.001)
    }

    func testIconSizeBelowRangeIsClampedToLowerBound() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        store.iconSize = 3

        XCTAssertEqual(store.iconSize, 16, accuracy: 0.001)
    }

    func testIconSizePersistsAcrossStoreInstances() {
        let suite = makeSuite()
        defer { clear(suite) }

        SettingsStore(defaults: suite.defaults).iconSize = 22

        XCTAssertEqual(SettingsStore(defaults: suite.defaults).iconSize, 22, accuracy: 0.001)
    }

    func testStoredValueOutsideRangeIsClampedOnLoad() {
        let suite = makeSuite()
        defer { clear(suite) }
        suite.defaults.set(120, forKey: SettingsStore.iconSizeDefaultsKey)

        XCTAssertEqual(SettingsStore(defaults: suite.defaults).iconSize, 36, accuracy: 0.001)
    }

    func testStoredNonNumericValueFallsBackToDefault() {
        let suite = makeSuite()
        defer { clear(suite) }
        suite.defaults.set("huge", forKey: SettingsStore.iconSizeDefaultsKey)

        XCTAssertEqual(SettingsStore(defaults: suite.defaults).iconSize, 24, accuracy: 0.001)
    }

    func testClampHelperRejectsNonFiniteValues() {
        XCTAssertEqual(SettingsStore.clampedIconSize(.nan), 24, accuracy: 0.001)
        XCTAssertEqual(SettingsStore.clampedIconSize(.infinity), 24, accuracy: 0.001)
        XCTAssertEqual(SettingsStore.clampedIconSize(-.infinity), 24, accuracy: 0.001)
        XCTAssertEqual(SettingsStore.clampedBatterySymbolScale(.nan), 1, accuracy: 0.001)
        XCTAssertEqual(SettingsStore.clampedBatterySymbolScale(.infinity), 1, accuracy: 0.001)
        XCTAssertEqual(
            SettingsStore.clampedBluetoothSymbolScale(.nan),
            SettingsStore.defaultBluetoothSymbolScale,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SettingsStore.clampedBluetoothSymbolScale(.infinity),
            SettingsStore.defaultBluetoothSymbolScale,
            accuracy: 0.001
        )
    }

    func testIconSizeChangeNotifiesSubscribers() {
        let store = SettingsStore(defaults: makeSuite().defaults)
        var received: [Double] = []
        let cancellable = store.$iconSize.sink { received.append($0) }

        store.iconSize = 21

        withExtendedLifetime(cancellable) {
            XCTAssertEqual(received, [24, 21])
        }
    }

    func testOutputDeviceDisplayDefaults() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        XCTAssertEqual(SettingsStore.outputDeviceLimitRange, 1...20)
        XCTAssertEqual(store.maxVisibleOutputDevices, 5)
        XCTAssertFalse(store.alwaysShowsAllOutputDevices)
        XCTAssertEqual(store.visibleOutputDeviceLimit, 5)
    }

    func testOutputDeviceDisplaySettingsPersist() {
        let suite = makeSuite()
        defer { clear(suite) }

        let first = SettingsStore(defaults: suite.defaults)
        first.maxVisibleOutputDevices = 8
        first.alwaysShowsAllOutputDevices = true

        let second = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(second.maxVisibleOutputDevices, 8)
        XCTAssertTrue(second.alwaysShowsAllOutputDevices)
        XCTAssertNil(second.visibleOutputDeviceLimit)
    }

    func testMaxVisibleOutputDevicesIsClamped() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        store.maxVisibleOutputDevices = 50
        XCTAssertEqual(store.maxVisibleOutputDevices, 20)

        store.maxVisibleOutputDevices = 0
        XCTAssertEqual(store.maxVisibleOutputDevices, 1)
    }

    func testBluetoothDeviceListDefaults() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        XCTAssertEqual(SettingsStore.bluetoothDeviceLimitRange, 1...20)
        XCTAssertTrue(store.showsBluetoothDeviceList)
        XCTAssertEqual(store.maxVisibleBluetoothDevices, 5)
        XCTAssertEqual(store.bluetoothDeviceOrder, [])
        XCTAssertEqual(
            store.bluetoothDeviceListOptions,
            BluetoothDeviceListOptions(
                showsList: true,
                maxVisibleDevices: 5,
                order: [],
                hidesGhostDevices: true,
                hiddenDeviceAddresses: []
            )
        )
    }

    func testBluetoothDeviceListSettingsPersist() {
        let suite = makeSuite()
        defer { clear(suite) }

        let first = SettingsStore(defaults: suite.defaults)
        first.showsBluetoothDeviceList = false
        first.maxVisibleBluetoothDevices = 8

        let second = SettingsStore(defaults: suite.defaults)
        XCTAssertFalse(second.showsBluetoothDeviceList)
        XCTAssertEqual(second.maxVisibleBluetoothDevices, 8)
    }

    func testMaxVisibleBluetoothDevicesIsClamped() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        store.maxVisibleBluetoothDevices = 50
        XCTAssertEqual(store.maxVisibleBluetoothDevices, 20)

        store.maxVisibleBluetoothDevices = 0
        XCTAssertEqual(store.maxVisibleBluetoothDevices, 1)
    }

    func testMovingBluetoothDevicesPersistsNormalizedAddressOrder() {
        let suite = makeSuite()
        defer { clear(suite) }

        let devices = [
            makeBluetoothDevice(address: "AC:90:85:C2:9C:1F", name: "AirPods"),
            makeBluetoothDevice(address: "D3:6D:6C:40:A3:2E", name: "MX Keys"),
            makeBluetoothDevice(address: "AA:BB:CC:DD:EE:FF", name: "Mouse")
        ]
        let store = SettingsStore(defaults: suite.defaults)

        store.moveBluetoothDevices(fromOffsets: IndexSet(integer: 2), toOffset: 0, in: devices)

        XCTAssertEqual(
            store.bluetoothDeviceOrder,
            ["AABBCCDDEEFF", "AC9085C29C1F", "D36D6C40A32E"]
        )
        XCTAssertEqual(
            SettingsStore(defaults: suite.defaults).bluetoothDeviceOrder,
            ["AABBCCDDEEFF", "AC9085C29C1F", "D36D6C40A32E"]
        )
    }

    func testManuallyHiddenBluetoothDevicesPersistAndNormalize() {
        let suite = makeSuite()
        defer { clear(suite) }

        let store = SettingsStore(defaults: suite.defaults)
        store.setBluetoothDeviceHidden("AC:90:85:C2:9C:1F", hidden: true)
        XCTAssertEqual(store.hiddenBluetoothDeviceAddresses, ["AC9085C29C1F"])

        // A second store reading the same suite sees the hide and feeds it into
        // the derived panel options.
        let reopened = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(reopened.hiddenBluetoothDeviceAddresses, ["AC9085C29C1F"])
        XCTAssertTrue(
            reopened.bluetoothDeviceListOptions.hiddenDeviceAddresses.contains("AC9085C29C1F")
        )

        store.setBluetoothDeviceHidden("AC:90:85:C2:9C:1F", hidden: false)
        XCTAssertFalse(store.hiddenBluetoothDeviceAddresses.contains("AC9085C29C1F"))
        XCTAssertEqual(SettingsStore(defaults: suite.defaults).hiddenBluetoothDeviceAddresses, [])
    }

    func testHidesGhostBluetoothDevicesTogglesAndPersists() {
        let suite = makeSuite()
        defer { clear(suite) }

        let store = SettingsStore(defaults: suite.defaults)
        XCTAssertTrue(store.hidesGhostBluetoothDevices)

        store.hidesGhostBluetoothDevices = false
        XCTAssertFalse(store.hidesGhostBluetoothDevices)
        XCTAssertFalse(
            SettingsStore(defaults: suite.defaults).bluetoothDeviceListOptions.hidesGhostDevices
        )
    }

    func testRevealedGhostBluetoothDevicesPersistAndNormalize() {
        let suite = makeSuite()
        defer { clear(suite) }

        let store = SettingsStore(defaults: suite.defaults)
        store.setBluetoothGhostRevealed("AC:90:85:C2:9C:1F", revealed: true)
        XCTAssertEqual(store.revealedGhostBluetoothDeviceAddresses, ["AC9085C29C1F"])

        // A second store reading the same suite sees the reveal and feeds it into
        // the derived panel options, overriding the default ghost filter.
        let reopened = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(reopened.revealedGhostBluetoothDeviceAddresses, ["AC9085C29C1F"])
        XCTAssertTrue(
            reopened.bluetoothDeviceListOptions.revealedGhostDeviceAddresses.contains("AC9085C29C1F")
        )

        store.setBluetoothGhostRevealed("AC:90:85:C2:9C:1F", revealed: false)
        XCTAssertFalse(store.revealedGhostBluetoothDeviceAddresses.contains("AC9085C29C1F"))
        XCTAssertEqual(SettingsStore(defaults: suite.defaults).revealedGhostBluetoothDeviceAddresses, [])
    }

    func testMovingBluetoothDevicesIgnoresOutOfRangeOffsets() {
        let store = SettingsStore(defaults: makeSuite().defaults)
        let devices = [makeBluetoothDevice(address: "AC:90:85:C2:9C:1F", name: "AirPods")]

        store.moveBluetoothDevices(fromOffsets: IndexSet(integer: 5), toOffset: 0, in: devices)
        XCTAssertEqual(store.bluetoothDeviceOrder, [])

        store.moveBluetoothDevices(fromOffsets: IndexSet(), toOffset: 0, in: devices)
        XCTAssertEqual(store.bluetoothDeviceOrder, [])
    }

    /// A destination past the last slot is rejected outright rather than
    /// clamped, so a move SwiftUI could never produce cannot rewrite the order.
    /// The valid destination at the end (`devices.count`) still goes through.
    func testMovingBluetoothDevicesIgnoresAnOutOfRangeDestination() {
        let suite = makeSuite()
        defer { clear(suite) }

        let devices = [
            makeBluetoothDevice(address: "AC:90:85:C2:9C:1F", name: "AirPods"),
            makeBluetoothDevice(address: "D3:6D:6C:40:A3:2E", name: "MX Keys")
        ]
        let store = SettingsStore(defaults: suite.defaults)

        store.moveBluetoothDevices(fromOffsets: IndexSet(integer: 0), toOffset: 3, in: devices)
        XCTAssertEqual(store.bluetoothDeviceOrder, [], "an out-of-range destination must be ignored")

        store.moveBluetoothDevices(fromOffsets: IndexSet(integer: 0), toOffset: 2, in: devices)
        XCTAssertEqual(
            store.bluetoothDeviceOrder,
            ["D36D6C40A32E", "AC9085C29C1F"],
            "the destination at the end of the list is in range and must move the device"
        )
    }

    func testMovingOutputDevicesPersistsCustomOrder() {
        let suite = makeSuite()
        defer { clear(suite) }

        let devices = [
            makeOutputDevice(id: 1, uid: "device-a"),
            makeOutputDevice(id: 2, uid: "device-b"),
            makeOutputDevice(id: 3, uid: "device-c")
        ]
        let store = SettingsStore(defaults: suite.defaults)

        store.moveOutputDevices(
            fromOffsets: IndexSet(integer: 2),
            toOffset: 0,
            in: devices
        )

        XCTAssertEqual(store.outputDeviceOrder, ["device-c", "device-a", "device-b"])
        XCTAssertEqual(
            SettingsStore(defaults: suite.defaults)
                .orderedOutputDevices(devices)
                .compactMap(\.uid),
            ["device-c", "device-a", "device-b"]
        )
    }

    func testUnlistedOutputDevicesAreAppendedAfterCustomOrder() {
        let suite = makeSuite()
        defer { clear(suite) }

        let devices = [
            makeOutputDevice(id: 1, uid: "device-a"),
            makeOutputDevice(id: 2, uid: "device-b")
        ]
        let store = SettingsStore(defaults: suite.defaults)
        store.moveOutputDevices(
            fromOffsets: IndexSet(integer: 1),
            toOffset: 0,
            in: devices
        )

        let updatedDevices = devices + [
            makeOutputDevice(id: 3, uid: "device-c")
        ]

        XCTAssertEqual(
            store.orderedOutputDevices(updatedDevices).compactMap(\.uid),
            ["device-b", "device-a", "device-c"]
        )
    }

    func testPopupSectionOrderDefaultsToBatteryNetworkVPNBluetoothVolumeAudioInput() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        XCTAssertEqual(
            store.popupSectionOrder,
            [.battery, .network, .vpn, .bluetooth, .volume, .audioInput]
        )
    }

    func testPopupVolumeScrollDefaultsToEverywhereSystemDirectionAndNaturalScrollingOff() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        XCTAssertTrue(store.popupScrollAdjustsVolume)
        XCTAssertEqual(store.popupVolumeScrollScope, .panel)
        XCTAssertEqual(store.popupVolumeScrollDirection, .up)
        XCTAssertFalse(store.popupVolumeNaturalScrolling)
    }

    func testPopupVolumeScrollChoicesPersistAcrossStoreInstances() {
        let suite = makeSuite()
        defer { clear(suite) }

        let first = SettingsStore(defaults: suite.defaults)
        first.popupScrollAdjustsVolume = false
        first.popupVolumeScrollScope = .volumeControl
        first.popupVolumeScrollDirection = .down
        first.popupVolumeNaturalScrolling = true

        let second = SettingsStore(defaults: suite.defaults)
        XCTAssertFalse(second.popupScrollAdjustsVolume)
        XCTAssertEqual(second.popupVolumeScrollScope, .volumeControl)
        XCTAssertEqual(second.popupVolumeScrollDirection, .down)
        XCTAssertTrue(second.popupVolumeNaturalScrolling)
    }

    func testPopupVolumeNaturalScrollingFallsBackToOffForNonBooleanStoredValue() {
        let suite = makeSuite()
        defer { clear(suite) }
        suite.defaults.set(
            "yes",
            forKey: SettingsStore.popupVolumeNaturalScrollingDefaultsKey
        )

        let store = SettingsStore(defaults: suite.defaults)

        XCTAssertFalse(store.popupVolumeNaturalScrolling)
    }

    func testUnknownStoredPopupVolumeScrollValuesFallBackToDefaults() {
        let suite = makeSuite()
        defer { clear(suite) }
        suite.defaults.set(
            "nowhere",
            forKey: SettingsStore.popupVolumeScrollScopeDefaultsKey
        )
        suite.defaults.set(
            "sideways",
            forKey: SettingsStore.popupVolumeScrollDirectionDefaultsKey
        )

        let store = SettingsStore(defaults: suite.defaults)

        XCTAssertEqual(store.popupVolumeScrollScope, .panel)
        XCTAssertEqual(store.popupVolumeScrollDirection, .up)
        XCTAssertFalse(store.popupVolumeNaturalScrolling)
    }

    func testPopupVolumeScrollOptionsExposeStableChoices() {
        XCTAssertEqual(PopupVolumeScrollScope.allCases, [.panel, .volumeControl])
        XCTAssertEqual(PopupVolumeScrollDirection.allCases, [.up, .down])
        XCTAssertEqual(PopupVolumeScrollScope.panel.id, .panel)
        XCTAssertEqual(PopupVolumeScrollDirection.up.id, .up)
        XCTAssertTrue(PopupVolumeScrollDirection.up.increasesWithScrollUp)
        XCTAssertFalse(PopupVolumeScrollDirection.down.increasesWithScrollUp)
    }

    func testInputSectionAppendsToOldOrderButDefaultsOff() {
        let freshSuite = makeSuite()
        defer { clear(freshSuite) }
        XCTAssertFalse(
            SettingsStore(defaults: freshSuite.defaults).enabledPopupSections.contains(.audioInput)
        )

        let suite = makeSuite()
        defer { clear(suite) }
        suite.defaults.set(
            ["volume", "battery"],
            forKey: SettingsStore.popupSectionOrderDefaultsKey
        )
        suite.defaults.set(
            ["volume", "battery"],
            forKey: SettingsStore.enabledPopupSectionsDefaultsKey
        )
        let store = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(
            store.popupSectionOrder,
            [.volume, .battery, .network, .vpn, .bluetooth, .audioInput]
        )
        XCTAssertFalse(store.enabledPopupSections.contains(.audioInput))
        store.setPopupSection(.audioInput, enabled: true)
        XCTAssertTrue(
            SettingsStore(defaults: suite.defaults).visiblePopupSections.contains(.audioInput)
        )
    }

    func testPopupSectionVisibilityDefaultsToEverythingExceptBluetooth() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        XCTAssertEqual(
            store.enabledPopupSections,
            Set([.battery, .network, .vpn, .volume])
        )
        XCTAssertEqual(
            store.visiblePopupSections,
            [.battery, .network, .vpn, .volume]
        )
    }

    func testPopupSectionVisibilityFiltersWithoutChangingStoredOrder() {
        let suite = makeSuite()
        defer { clear(suite) }

        let first = SettingsStore(defaults: suite.defaults)
        first.setPopupSection(.network, enabled: false)
        first.setPopupSection(.bluetooth, enabled: true)

        XCTAssertEqual(
            first.popupSectionOrder,
            [.battery, .network, .vpn, .bluetooth, .volume, .audioInput]
        )
        XCTAssertEqual(
            first.visiblePopupSections,
            [.battery, .vpn, .bluetooth, .volume]
        )

        let second = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(
            second.enabledPopupSections,
            Set([.battery, .vpn, .bluetooth, .volume])
        )
    }

    func testMovingPopupSectionsPersistsOrder() {
        let suite = makeSuite()
        defer { clear(suite) }

        let store = SettingsStore(defaults: suite.defaults)
        store.movePopupSections(
            fromOffsets: IndexSet(integer: 4),
            toOffset: 0
        )

        XCTAssertEqual(
            store.popupSectionOrder,
            [.volume, .battery, .network, .vpn, .bluetooth, .audioInput]
        )
        XCTAssertEqual(
            SettingsStore(defaults: suite.defaults).popupSectionOrder,
            [.volume, .battery, .network, .vpn, .bluetooth, .audioInput]
        )
    }

    func testStoredPopupSectionOrderIsSanitizedAndCompleted() {
        let suite = makeSuite()
        defer { clear(suite) }

        suite.defaults.set(
            ["volume", "unknown", "volume", "network"],
            forKey: SettingsStore.popupSectionOrderDefaultsKey
        )

        let store = SettingsStore(defaults: suite.defaults)

        XCTAssertEqual(
            store.popupSectionOrder,
            [.volume, .network, .battery, .vpn, .bluetooth, .audioInput]
        )
    }

    func testStoredPopupSectionVisibilityIgnoresUnknownValues() {
        let suite = makeSuite()
        defer { clear(suite) }

        suite.defaults.set(
            ["network", "unknown", "network"],
            forKey: SettingsStore.enabledPopupSectionsDefaultsKey
        )
        // The one-shot VPN migration is covered by `VPNRowSettingsTests`; this
        // test is about unknown raw values, so the marker is set to keep the
        // stored list the only input.
        suite.defaults.set(
            true,
            forKey: SettingsStore.vpnPopupSectionIntroducedDefaultsKey
        )

        let store = SettingsStore(defaults: suite.defaults)

        XCTAssertEqual(store.enabledPopupSections, Set([.network]))
        XCTAssertEqual(store.visiblePopupSections, [.network])
    }

    func testPopupSectionMetadataIncludesVPNAndBluetooth() {
        XCTAssertEqual(PopupSection.vpn.titleKey, .vpnTitle)
        XCTAssertNotNil(
            NSImage(
                systemSymbolName: PopupSection.vpn.systemImage,
                accessibilityDescription: nil
            )
        )
        XCTAssertEqual(PopupSection.bluetooth.titleKey, .bluetoothTitle)
        XCTAssertNotNil(BluetoothIcon.templateImage)
        XCTAssertNotNil(
            NSImage(
                systemSymbolName: PopupSection.bluetooth.systemImage,
                accessibilityDescription: nil
            )
        )
    }

    func testAudioInputPopupSectionMetadata() {
        XCTAssertEqual(PopupSection.audioInput.titleKey, .settingsPopupOrderAudioInput)
        XCTAssertEqual(PopupSection.audioInput.systemImage, "mic")
        XCTAssertNotNil(
            NSImage(
                systemSymbolName: PopupSection.audioInput.systemImage,
                accessibilityDescription: nil
            )
        )
    }

    func testPopupSectionMetadataNamesTheNetworkRowForBothLinks() {
        // The row is the Wi-Fi row while Wi-Fi is primary and the wired row
        // while a cable is, so the settings list may not call it Wi-Fi.
        XCTAssertEqual(PopupSection.network.titleKey, .settingsPopupOrderNetwork)
        XCTAssertNotNil(
            NSImage(
                systemSymbolName: PopupSection.network.systemImage,
                accessibilityDescription: nil
            )
        )
    }

    func testIconGuideCallsTheCentreOfTheIconNetwork() {
        // The guide labels the same part of the icon the popup section does, and
        // its own explanation already says the symbol follows the connection
        // type. A label reading Wi-Fi above that text contradicts it.
        XCTAssertEqual(IconGuidePart.network.titleKey, .settingsPopupOrderNetwork)
    }

    func testEveryConfigurableSizeRendersAtThatSize() throws {

        for value in stride(
            from: SettingsStore.iconSizeRange.lowerBound,
            through: SettingsStore.iconSizeRange.upperBound,
            by: 1
        ) {
            let image = try XCTUnwrap(menuBarFixtureImage(
                snapshot: .placeholder,
                size: value
            ))

            XCTAssertEqual(image.size.width, value, accuracy: 0.01, "width at \(value) pt")
            XCTAssertEqual(image.size.height, value, accuracy: 0.01, "height at \(value) pt")
        }
    }

    func testAppIconPlacementDefaultsToMenuBar() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        XCTAssertEqual(store.appIconPlacement, .menuBar)
    }

    func testAppIconPlacementPersistsAcrossStoreInstances() {
        let suite = makeSuite()
        defer { clear(suite) }

        let first = SettingsStore(defaults: suite.defaults)
        first.appIconPlacement = .both

        XCTAssertEqual(SettingsStore(defaults: suite.defaults).appIconPlacement, .both)
    }

    func testUnknownAppIconPlacementFallsBackToMenuBar() {
        let suite = makeSuite()
        defer { clear(suite) }
        suite.defaults.set("neither", forKey: SettingsStore.appIconPlacementDefaultsKey)

        XCTAssertEqual(SettingsStore(defaults: suite.defaults).appIconPlacement, .menuBar)
    }

    func testAppIconPlacementPublishesChanges() {
        let suite = makeSuite()
        defer { clear(suite) }

        let store = SettingsStore(defaults: suite.defaults)
        var published: [AppIconPlacement] = []
        let cancellable = store.$appIconPlacement.dropFirst().sink { published.append($0) }
        defer { cancellable.cancel() }

        store.appIconPlacement = .dock
        store.appIconPlacement = .both

        XCTAssertEqual(published, [.dock, .both])
    }

    func testDockIconBackgroundPreferenceDefaultsToSystem() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        XCTAssertEqual(store.dockIconBackgroundPreference, .system)
    }

    func testDockIconBackgroundPreferencePersistsAcrossStoreInstances() {
        let suite = makeSuite()
        defer { clear(suite) }

        let first = SettingsStore(defaults: suite.defaults)
        first.dockIconBackgroundPreference = .light

        XCTAssertEqual(
            SettingsStore(defaults: suite.defaults).dockIconBackgroundPreference,
            .light
        )
    }

    func testUnknownDockIconBackgroundPreferenceFallsBackToSystem() {
        let suite = makeSuite()
        defer { clear(suite) }
        suite.defaults.set(
            "rainbow",
            forKey: SettingsStore.dockIconBackgroundPreferenceDefaultsKey
        )

        XCTAssertEqual(
            SettingsStore(defaults: suite.defaults).dockIconBackgroundPreference,
            .system
        )
    }

    func testDockIconBackgroundPreferencePublishesChanges() {
        let suite = makeSuite()
        defer { clear(suite) }

        let store = SettingsStore(defaults: suite.defaults)
        var published: [DockIconBackgroundPreference] = []
        let cancellable = store.$dockIconBackgroundPreference.dropFirst().sink {
            published.append($0)
        }
        defer { cancellable.cancel() }

        store.dockIconBackgroundPreference = .light
        store.dockIconBackgroundPreference = .system

        XCTAssertEqual(published, [.light, .system])
    }

    func testRingStrokeStyleDefaultsToRegularAndFeedsOptions() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        XCTAssertEqual(store.ringStrokeStyle, .regular)
        XCTAssertEqual(store.batteryIconOptions.ringStrokeScale, RingStrokeStyle.regular.scale)
        XCTAssertEqual(store.volumeIconOptions.ringStrokeScale, RingStrokeStyle.regular.scale)
    }

    func testRingStrokeStylePersistsAndFeedsOptions() {
        let suite = makeSuite()
        defer { clear(suite) }

        let first = SettingsStore(defaults: suite.defaults)
        first.ringStrokeStyle = .bold
        XCTAssertEqual(first.batteryIconOptions.ringStrokeScale, RingStrokeStyle.bold.scale)
        XCTAssertEqual(first.volumeIconOptions.ringStrokeScale, RingStrokeStyle.bold.scale)

        let second = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(second.ringStrokeStyle, .bold)
        XCTAssertEqual(second.batteryIconOptions.ringStrokeScale, RingStrokeStyle.bold.scale)
        XCTAssertEqual(second.volumeIconOptions.ringStrokeScale, RingStrokeStyle.bold.scale)
    }

    func testUnknownRingStrokeStyleFallsBackToRegular() {
        let suite = makeSuite()
        defer { clear(suite) }
        suite.defaults.set(
            "ultra-heavy",
            forKey: SettingsStore.ringStrokeStyleDefaultsKey
        )

        let store = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(store.ringStrokeStyle, .regular)
        XCTAssertEqual(store.batteryIconOptions.ringStrokeScale, RingStrokeStyle.regular.scale)
        XCTAssertEqual(store.volumeIconOptions.ringStrokeScale, RingStrokeStyle.regular.scale)
    }

    func testRingStrokeStylePublishesChanges() {
        let suite = makeSuite()
        defer { clear(suite) }

        let store = SettingsStore(defaults: suite.defaults)
        var published: [RingStrokeStyle] = []
        let cancellable = store.$ringStrokeStyle.dropFirst().sink {
            published.append($0)
        }
        defer { cancellable.cancel() }

        store.ringStrokeStyle = .light
        store.ringStrokeStyle = .bold

        XCTAssertEqual(published, [.light, .bold])
    }

    func testRingStrokeStyleAcceptsDescriptiveSynonyms() {
        XCTAssertEqual(RingStrokeStyle(rawValue: "standard"), .light)
        XCTAssertEqual(RingStrokeStyle(rawValue: "normal"), .regular)
        XCTAssertEqual(RingStrokeStyle(rawValue: "heavy"), .bold)
        XCTAssertNil(RingStrokeStyle(rawValue: "ultra-heavy"))
        XCTAssertEqual(RingStrokeStyle.allCases, [.light, .regular, .bold])
    }

    /// `.standard` is what the previews, the icon guide, and many tests use, so
    /// it has to track the enum rather than a second hard-coded number.
    func testStandardOptionsShareTheRegularStrokeWidth() {
        XCTAssertEqual(BatteryIconOptions.defaultRingStrokeScale, RingStrokeStyle.regular.scale)
        XCTAssertEqual(VolumeIconOptions.defaultRingStrokeScale, RingStrokeStyle.regular.scale)
        XCTAssertEqual(BatteryIconOptions.standard.ringStrokeScale, RingStrokeStyle.regular.scale)
        XCTAssertEqual(VolumeIconOptions.standard.ringStrokeScale, RingStrokeStyle.regular.scale)
    }

    func testVolumeDotRadiusScalesMoreGentlyThanTheRing() {
        XCTAssertEqual(
            VolumeIconOptions(ringStrokeScale: RingStrokeStyle.light.scale).dotRadiusScale,
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            VolumeIconOptions(ringStrokeScale: RingStrokeStyle.regular.scale).dotRadiusScale,
            1.125,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            VolumeIconOptions(ringStrokeScale: RingStrokeStyle.bold.scale).dotRadiusScale,
            1.25,
            accuracy: 0.0001
        )
    }

    private func makeSuite() -> (defaults: UserDefaults, name: String) {
        let name = "StatusTrioCoreTests.SettingsStore.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            fatalError("could not create isolated user defaults suite")
        }
        defaults.removeTestSuite(named: name)
        // Discard the suite when the test ends, so a test that forgets to call
        // `clear` still cannot leave a preference file behind.
        addTeardownBlock { TestUserDefaults.removeSuite(named: name) }
        return (defaults, name)
    }

    private func clear(_ suite: (defaults: UserDefaults, name: String)) {
        suite.defaults.removeTestSuite(named: suite.name)
    }

    private func makeOutputDevice(id: AudioDeviceID, uid: String) -> AudioOutputDevice {
        AudioOutputDevice(
            id: id,
            name: uid,
            uid: uid,
            isCurrent: false
        )
    }

    private func makeBluetoothDevice(address: String, name: String) -> BluetoothDevice {
        BluetoothDevice(id: address, name: name, kind: .audio, isConnected: true)
    }
}
