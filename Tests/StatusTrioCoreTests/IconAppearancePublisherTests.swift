import Combine
import XCTest
@testable import StatusTrioCore

/// The menu bar and the Dock both render from `SettingsStore.iconAppearancePublisher`.
///
/// These tests are the regression guard for the "the icon only catches up on the
/// next status poll" bug: a setting that the chain forgets publishes nothing, and
/// the icon then stays stale until something else redraws it.
@MainActor
final class IconAppearancePublisherTests: XCTestCase {
    func testEveryIconSettingPublishesAnAppearanceThatInvalidatesTheIcon() throws {
        for mutation in Self.iconMutations {
            let settings = makeSettings()
            var appearances: [StatusIconAppearance] = []
            let cancellable = settings.iconAppearancePublisher
                .sink { appearances.append($0) }
            defer { cancellable.cancel() }

            let baseline = try XCTUnwrap(appearances.last, mutation.name)

            mutation.apply(settings)

            let updated = try XCTUnwrap(appearances.last, mutation.name)
            XCTAssertNotEqual(
                updated,
                baseline,
                "\(mutation.name) must publish a new appearance"
            )

            var menuBarCache = StatusBarRenderCache()
            let baselineMenuKey = menuBarKey(baseline)
            let updatedMenuKey = menuBarKey(updated)
            XCTAssertTrue(menuBarCache.needsRender(baselineMenuKey))
            menuBarCache.recordSuccessfulRender(baselineMenuKey)
            XCTAssertEqual(
                menuBarCache.needsRender(updatedMenuKey),
                updatedMenuKey != baselineMenuKey,
                "\(mutation.name) redraws only when its mapped scene or menu-bar size changes"
            )

            var dockCache = DockIconRenderCache()
            let baselineDockKey = dockKey(baseline)
            let updatedDockKey = dockKey(updated)
            XCTAssertTrue(dockCache.needsRender(baselineDockKey))
            dockCache.recordSuccessfulRender(baselineDockKey)
            XCTAssertEqual(
                dockCache.needsRender(updatedDockKey),
                updatedDockKey != baselineDockKey,
                "\(mutation.name) invalidates Dock only when its mapped scene changes"
            )
        }
    }

    /// The controllers read the appearance back from the store for renders that
    /// the publisher did not trigger, so the two have to agree. `@Published`
    /// publishes before the stored value changes, which is exactly what a
    /// read-back would get wrong.
    func testLiveAppearanceMatchesTheLastPublishedValue() throws {
        let settings = makeSettings()
        var appearances: [StatusIconAppearance] = []
        let cancellable = settings.iconAppearancePublisher
            .sink { appearances.append($0) }
        defer { cancellable.cancel() }

        settings.showsBatteryPercentage = false
        settings.ringStrokeStyle = .bold
        settings.volumeDisplayStyle = .arc
        settings.bluetoothSymbolScale = 1.4

        XCTAssertEqual(
            appearances.last,
            StatusIconAppearance(settings: settings)
        )
    }

    /// Settings that cannot change the artwork must not redraw it, including the
    /// Dock-only background preference, which the Dock controller subscribes to
    /// on its own.
    func testSettingsThatCannotChangeTheIconPublishNothing() {
        let settings = makeSettings()
        var appearances: [StatusIconAppearance] = []
        let cancellable = settings.iconAppearancePublisher
            .sink { appearances.append($0) }
        defer { cancellable.cancel() }

        let publishedCount = appearances.count

        settings.refreshIntervalSeconds = 30
        settings.showsBluetoothBatteryLevels = true
        settings.hasCompletedIconGuideOnboarding = true
        settings.popupScrollAdjustsVolume = false
        settings.popupVolumeScrollScope = .volumeControl
        settings.popupVolumeScrollDirection = .down
        settings.popupVolumeNaturalScrolling = true
        settings.maxVisibleOutputDevices = 8
        settings.alwaysShowsAllOutputDevices = true
        settings.dockIconBackgroundPreference = .dark

        XCTAssertEqual(appearances.count, publishedCount)
    }

    /// One change publishes one appearance. A setting that two option structs
    /// share must not publish a half-updated intermediate that a controller could
    /// render.
    func testSharedRingStrokeStylePublishesASingleConsistentAppearance() {
        let settings = makeSettings()
        var appearances: [StatusIconAppearance] = []
        let cancellable = settings.iconAppearancePublisher
            .sink { appearances.append($0) }
        defer { cancellable.cancel() }

        let publishedCount = appearances.count
        settings.ringStrokeStyle = .bold

        XCTAssertEqual(appearances.count, publishedCount + 1)

        let appearance = appearances.last
        XCTAssertEqual(appearance?.batteryOptions.ringStrokeScale, RingStrokeStyle.bold.scale)
        XCTAssertEqual(appearance?.volumeOptions.ringStrokeScale, RingStrokeStyle.bold.scale)
    }

    func testIconPresentationPublisherIncludesEveryAppearanceSettingAndTestMode() throws {
        let settings = makeSettings()
        var values: [IconPresentationSettings] = []
        let cancellable = settings.iconPresentationPublisher.sink { values.append($0) }
        defer { cancellable.cancel() }

        for mutation in Self.iconMutations {
            let previousCount = values.count
            mutation.apply(settings)
            XCTAssertEqual(values.count, previousCount + 1, "\(mutation.name) publishes once")
            let value = try XCTUnwrap(values.last)
            let appearance = StatusIconAppearance(settings: settings)
            XCTAssertEqual(value.menuBarSize, appearance.iconSize)
            XCTAssertEqual(value.configuration.battery, appearance.batteryOptions)
            XCTAssertEqual(value.configuration.connection, appearance.connectionOptions)
            XCTAssertEqual(value.configuration.volume, appearance.volumeOptions)
            XCTAssertEqual(value.configuration.bluetooth, appearance.bluetoothAudioOptions)
        }

        settings.showsChargingEffect = true
        let previousCount = values.count
        settings.setChargingEffectTestEnabled(true)
        XCTAssertEqual(values.count, previousCount + 1)
        XCTAssertEqual(values.last?.testsChargingEffect, true)

        let afterIconSettingCount = values.count
        settings.refreshIntervalSeconds = 30
        settings.showsBluetoothBatteryLevels = true
        settings.hasCompletedIconGuideOnboarding = true
        settings.dockIconBackgroundPreference = .dark
        XCTAssertEqual(values.count, afterIconSettingCount)
    }

    // MARK: - Helpers

    private static let menuBarOnlyMutationName = "iconSize"

    private struct IconMutation {
        let name: String
        let apply: (SettingsStore) -> Void
    }

    private static let iconMutations: [IconMutation] = [
        IconMutation(name: menuBarOnlyMutationName) { $0.iconSize = 32 },
        IconMutation(name: "showsBatteryPercentage") { $0.showsBatteryPercentage = false },
        IconMutation(name: "showsChargingIndicator") { $0.showsChargingIndicator = false },
        IconMutation(name: "showsChargingEffect") { $0.showsChargingEffect = false },
        IconMutation(name: "showsChargingBoltHeartbeat") { $0.showsChargingBoltHeartbeat = false },
        IconMutation(name: "usesBatteryStatusColors") { $0.usesBatteryStatusColors = false },
        IconMutation(name: "batteryCriticalThreshold") { $0.batteryCriticalThreshold = 35 },
        IconMutation(name: "showsPercentageWhenConnected") {
            $0.showsPercentageWhenConnected = true
        },
        IconMutation(name: "showsBatteryPercentageInConnectionSlot") {
            $0.showsBatteryPercentageInConnectionSlot = true
        },
        IconMutation(name: "batterySymbolScale") { $0.batterySymbolScale = 1.05 },
        IconMutation(name: "showsWiFiIconForEthernet") { $0.showsWiFiIconForEthernet = true },
        IconMutation(name: "showsWiFiIconForHotspot") { $0.showsWiFiIconForHotspot = true },
        IconMutation(name: "showsWiFiIconForTemporaryConnection") {
            $0.showsWiFiIconForTemporaryConnection = true
        },
        IconMutation(name: "showsWiFiIconForInternetSharing") {
            $0.showsWiFiIconForInternetSharing = true
        },
        IconMutation(name: "wifiSymbolScale") { $0.wifiSymbolScale = 1.4 },
        IconMutation(name: "replacesNetworkIconWithBluetoothAudio") {
            $0.replacesNetworkIconWithBluetoothAudio = true
        },
        IconMutation(name: "usesBluetoothAudioVolumeColor") {
            $0.usesBluetoothAudioVolumeColor = true
        },
        IconMutation(name: "prioritizesNetworkErrorsOverBluetoothAudio") {
            $0.prioritizesNetworkErrorsOverBluetoothAudio = false
        },
        IconMutation(name: "bluetoothSymbolScale") { $0.bluetoothSymbolScale = 1.4 },
        IconMutation(name: "bluetoothNetworkIconDevice") {
            $0.setBluetoothNetworkIconDevice(address: "aa-bb-cc-dd-ee-ff", symbolName: "keyboard")
        },
        IconMutation(name: "ringStrokeStyle") { $0.ringStrokeStyle = .bold },
        IconMutation(name: "volumeDisplayStyle") { $0.volumeDisplayStyle = .arc }
    ]

    private var status: MenuBarStatus {
        MenuBarStatus(
            battery: BatteryStatus(
                rawPercentage: 68,
                isPresent: true,
                isCharging: false,
                isLowPowerMode: false,
                isConnectedToPower: false
            ),
            wifi: WiFiStatus(state: .connected, rssi: -52),
            connection: .wifi,
            volume: MenuBarVolumeStatus(scalar: 0.5, isMuted: false, deviceName: nil)
        )
    }

    private func menuBarKey(_ appearance: StatusIconAppearance) -> StatusBarRenderKey {
        StatusBarRenderKey(
            scene: scene(appearance),
            iconSize: appearance.iconSize,
            backingScale: 2,
            appearanceName: "darkAqua",
            phase: nil
        )
    }

    private func dockKey(_ appearance: StatusIconAppearance) -> DockIconRenderKey {
        DockIconRenderKey(
            scene: scene(appearance),
            backgroundStyle: .dark,
            pixelLength: DockIconRenderer.pixelSize
        )
    }

    private func scene(_ appearance: StatusIconAppearance) -> IconSceneState {
        let snapshot = StatusSnapshot(
            battery: status.battery,
            wifi: status.wifi,
            connection: status.connection,
            volume: VolumeStatus(
                scalar: status.volume.scalar,
                isMuted: status.volume.isMuted,
                deviceName: status.volume.deviceName,
                currentDevice: status.volume.currentDevice
            )
        )
        return IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
            configuration: IconPresentationConfiguration(
                battery: appearance.batteryOptions,
                connection: appearance.connectionOptions,
                volume: appearance.volumeOptions,
                bluetooth: appearance.bluetoothAudioOptions
            )
        )
    }

    private func makeSettings() -> SettingsStore {
        let suiteName = "StatusTrioCoreTests.IconAppearance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removeTestSuite(named: suiteName)
        addTeardownBlock { TestUserDefaults.removeSuite(named: suiteName) }
        return SettingsStore(defaults: defaults)
    }
}
