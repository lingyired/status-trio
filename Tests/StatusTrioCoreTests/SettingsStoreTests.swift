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
        XCTAssertEqual(store.iconSize, 28, accuracy: 0.001)
    }

    func testRefreshIntervalDefaultsAndRange() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        XCTAssertEqual(SettingsStore.refreshIntervalRange, 5...60)
        XCTAssertEqual(store.refreshIntervalSeconds, 5, accuracy: 0.001)
        XCTAssertEqual(store.refreshInterval, .seconds(5))
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

    func testConnectionIconDisplayDefaults() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        XCTAssertFalse(store.showsWiFiIconForEthernet)
        XCTAssertFalse(store.showsWiFiIconForHotspot)
        XCTAssertFalse(store.showsWiFiIconForTemporaryConnection)
        XCTAssertFalse(store.showsWiFiIconForInternetSharing)
        XCTAssertEqual(store.connectionIconOptions, .standard)
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

        XCTAssertEqual(SettingsStore(defaults: suite.defaults).iconSize, 28, accuracy: 0.001)
    }

    func testClampHelperRejectsNonFiniteValues() {
        XCTAssertEqual(SettingsStore.clampedIconSize(.nan), 28, accuracy: 0.001)
        XCTAssertEqual(SettingsStore.clampedIconSize(.infinity), 28, accuracy: 0.001)
        XCTAssertEqual(SettingsStore.clampedIconSize(-.infinity), 28, accuracy: 0.001)
        XCTAssertEqual(SettingsStore.clampedBatterySymbolScale(.nan), 1, accuracy: 0.001)
        XCTAssertEqual(SettingsStore.clampedBatterySymbolScale(.infinity), 1, accuracy: 0.001)
    }

    func testIconSizeChangeNotifiesSubscribers() {
        let store = SettingsStore(defaults: makeSuite().defaults)
        var received: [Double] = []
        let cancellable = store.$iconSize.sink { received.append($0) }

        store.iconSize = 21

        withExtendedLifetime(cancellable) {
            XCTAssertEqual(received, [28, 21])
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

    func testPopupSectionOrderDefaultsToBatteryNetworkBluetoothVolume() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        XCTAssertEqual(store.popupSectionOrder, [.battery, .network, .bluetooth, .volume])
    }

    func testPopupSectionVisibilityDefaultsToEverythingExceptBluetooth() {
        let store = SettingsStore(defaults: makeSuite().defaults)

        XCTAssertEqual(
            store.enabledPopupSections,
            Set([.battery, .network, .volume])
        )
        XCTAssertEqual(
            store.visiblePopupSections,
            [.battery, .network, .volume]
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
            [.battery, .network, .bluetooth, .volume]
        )
        XCTAssertEqual(
            first.visiblePopupSections,
            [.battery, .bluetooth, .volume]
        )

        let second = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(second.enabledPopupSections, Set([.battery, .bluetooth, .volume]))
    }

    func testMovingPopupSectionsPersistsOrder() {
        let suite = makeSuite()
        defer { clear(suite) }

        let store = SettingsStore(defaults: suite.defaults)
        store.movePopupSections(
            fromOffsets: IndexSet(integer: 3),
            toOffset: 0
        )

        XCTAssertEqual(store.popupSectionOrder, [.volume, .battery, .network, .bluetooth])
        XCTAssertEqual(
            SettingsStore(defaults: suite.defaults).popupSectionOrder,
            [.volume, .battery, .network, .bluetooth]
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

        XCTAssertEqual(store.popupSectionOrder, [.volume, .network, .battery, .bluetooth])
    }

    func testStoredPopupSectionVisibilityIgnoresUnknownValues() {
        let suite = makeSuite()
        defer { clear(suite) }

        suite.defaults.set(
            ["network", "unknown", "network"],
            forKey: SettingsStore.enabledPopupSectionsDefaultsKey
        )

        let store = SettingsStore(defaults: suite.defaults)

        XCTAssertEqual(store.enabledPopupSections, Set([.network]))
        XCTAssertEqual(store.visiblePopupSections, [.network])
    }

    func testPopupSectionMetadataIncludesBluetooth() {
        XCTAssertEqual(PopupSection.bluetooth.titleKey, .bluetoothTitle)
        XCTAssertNotNil(BluetoothIcon.templateImage)
        XCTAssertNotNil(
            NSImage(
                systemSymbolName: PopupSection.bluetooth.systemImage,
                accessibilityDescription: nil
            )
        )
    }


    func testEveryConfigurableSizeRendersAtThatSize() throws {

        for value in stride(
            from: SettingsStore.iconSizeRange.lowerBound,
            through: SettingsStore.iconSizeRange.upperBound,
            by: 1
        ) {
            let image = StatusIconRenderer.image(
                snapshot: .placeholder,
                size: value
            )

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

    private func makeSuite() -> (defaults: UserDefaults, name: String) {
        let name = "StatusTrioCoreTests.SettingsStore.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            fatalError("could not create isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    private func clear(_ suite: (defaults: UserDefaults, name: String)) {
        suite.defaults.removePersistentDomain(forName: suite.name)
    }

    private func makeOutputDevice(id: AudioDeviceID, uid: String) -> AudioOutputDevice {
        AudioOutputDevice(
            id: id,
            name: uid,
            uid: uid,
            isCurrent: false
        )
    }
}
