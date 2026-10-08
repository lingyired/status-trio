import AppKit
import Foundation
import Testing
@testable import StatusTrioCore

@MainActor
struct StatusBarControllerVisibilityTests {
    @Test func testSwitchAnimatesTheMenuBarWhileTheRealBatteryIsUnplugged() async throws {
        let domain = "StatusBarChargingTest.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let battery = BatteryStatus(
            rawPercentage: 46,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        )
        let settings = SettingsStore(defaults: defaults)
        settings.setChargingEffectTestEnabled(true)
        settings.iconSize = 28
        let start = Date(timeIntervalSince1970: 1_000)
        var firstTimeRead = true
        let clock = ChargingEffectClock(
            now: {
                guard firstTimeRead else { return start.addingTimeInterval(2) }
                firstTimeRead = false
                return start
            },
            sleep: { _ in try await Task.sleep(for: .seconds(60)) }
        )
        clock.update(
            battery: ChargingEffectTestMode.battery(battery, enabled: true),
            enabled: settings.showsChargingEffect,
            reduceMotion: false,
            displayAsleep: false
        )
        defer { clock.stop() }
        let store = SystemStatusStore(
            batteryMonitor: IdleBatteryMonitor(),
            wifiMonitor: IdleWiFiMonitor(),
            volumeMonitor: IdleVolumeMonitor(),
            initialSnapshot: StatusSnapshot(battery: battery, wifi: .placeholder, volume: .placeholder)
        )
        let iconPresentation = makeTestIconPresentation(store: store, settings: settings)
        iconPresentation.start()
        defer { iconPresentation.stop() }
        let rasterFailure = RasterFailureSwitch()
        let controller = StatusBarController(
            store: store,
            settings: settings,
            iconPresentation: iconPresentation,
            localization: Localization(defaults: defaults, preferredLanguages: ["en"]),
            openSettings: {},
            quitAction: {},
            chargingEffectClock: clock,
            renderMenuBarIcon: { scene, size, scale, appearance, phase in
                guard !rasterFailure.isEnabled else { return nil }
                return StatusIconRenderer.image(
                    scene: scene,
                    size: CGFloat(size),
                    scale: scale,
                    appearance: appearance,
                    phase: phase
                )
            }
        )
        defer { controller.setVisible(false) }
        await Task.yield()

        #expect(store.snapshot.battery == battery)
        #expect(clock.isRunning)
        #expect(controller.cachedChargingFrameCount == 36)
        #expect(controller.hasLayerBackedAnimation)
        #expect(controller.presentedImageForTesting?.size.width == 28)

        settings.iconSize = 32
        controller.flushPendingPresentationForTesting()
        #expect(controller.hasLayerBackedAnimation)
        #expect(controller.presentedImageForTesting?.size.width == 32)

        settings.setChargingEffectTestEnabled(false)
        rasterFailure.isEnabled = true
        clock.update(battery: battery, enabled: true, reduceMotion: false, displayAsleep: false)
        #expect(!clock.isRunning)
        #expect(controller.cachedChargingFrameCount == 36)
        #expect(controller.hasLayerBackedAnimation)

        rasterFailure.isEnabled = false
        controller.refreshCurrentPresentation()
        #expect(controller.cachedChargingFrameCount == 0)
        #expect(controller.hasLayerBackedAnimation == false)
    }

    @Test func hiddenStatusItemReleasesAnimationResourcesWhenChargingStops() async throws {
        let domain = "StatusBarControllerVisibilityTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }

        let battery = BatteryStatus(
            rawPercentage: 62,
            isPresent: true,
            isCharging: true,
            isLowPowerMode: false,
            isConnectedToPower: true
        )
        let start = Date(timeIntervalSince1970: 1_000)
        var firstTimeRead = true
        let clock = ChargingEffectClock(
            now: {
                guard firstTimeRead else { return start.addingTimeInterval(2) }
                firstTimeRead = false
                return start
            },
            sleep: { _ in try await Task.sleep(for: .seconds(60)) }
        )
        clock.update(battery: battery, enabled: true, reduceMotion: false, displayAsleep: false)
        defer { clock.stop() }
        #expect(clock.phase?.kind == .steady)

        let store = SystemStatusStore(
            batteryMonitor: IdleBatteryMonitor(),
            wifiMonitor: IdleWiFiMonitor(),
            volumeMonitor: IdleVolumeMonitor(),
            initialSnapshot: StatusSnapshot(
                battery: battery,
                wifi: .placeholder,
                volume: .placeholder
            )
        )
        let settings = SettingsStore(defaults: defaults)
        let iconPresentation = makeTestIconPresentation(store: store, settings: settings)
        iconPresentation.start()
        defer { iconPresentation.stop() }
        let controller = StatusBarController(
            store: store,
            settings: settings,
            iconPresentation: iconPresentation,
            localization: Localization(defaults: defaults, preferredLanguages: ["en"]),
            openSettings: {},
            quitAction: {},
            chargingEffectClock: clock
        )
        defer { controller.setVisible(false) }
        await Task.yield()

        #expect(controller.cachedChargingFrameCount == 36)
        #expect(controller.hasLayerBackedAnimation)

        controller.setVisible(false)
        clock.update(
            battery: BatteryStatus(
                rawPercentage: 62,
                isPresent: true,
                isCharging: false,
                isLowPowerMode: false,
                isConnectedToPower: false
            ),
            enabled: true,
            reduceMotion: false,
            displayAsleep: false
        )

        #expect(clock.phase == nil)
        #expect(controller.cachedChargingFrameCount == 0)
        #expect(controller.hasLayerBackedAnimation == false)
    }
}

@MainActor
private final class RasterFailureSwitch {
    var isEnabled = false
}

@MainActor
private final class IdleBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>

    init() {
        (updates, _) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class IdleWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>

    init() {
        (updates, _) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class IdleVolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>

    init() {
        (updates, _) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func setDetailsVisible(_ visible: Bool) {}
}
