import AppKit
import Testing
@testable import StatusTrioCore

@MainActor
struct ChargingEffectControllerTests {
    @Test func menuBarTestModeDoesNotChangeDockArtworkOrRealBattery() throws {
        let battery = dockTestBattery(46, charging: false)
        let harness = try AppIconControllerHarness(
            initialPlacement: .dock,
            initialBattery: battery
        )
        harness.controller.start()
        defer {
            harness.controller.stop()
            harness.cleanUp()
        }
        let originalImage = try #require(harness.application.applicationIconImage)
        let originalRenderCount = harness.log.renderCount

        harness.settings.setChargingEffectTestEnabled(true)

        #expect(harness.store.snapshot.battery == battery)
        #expect(harness.log.lastScene != nil)
        #expect(harness.log.renderCount == originalRenderCount)
        #expect(harness.application.applicationIconImage === originalImage)
    }

    @Test func batteryLevelChangesStillUpdateStaticDockArtwork() async throws {
        let harness = try AppIconControllerHarness(
            initialPlacement: .dock,
            initialBattery: dockTestBattery(60, charging: true)
        )
        harness.controller.start()
        defer {
            harness.controller.stop()
            harness.cleanUp()
        }

        let increasedBattery = dockTestBattery(61, charging: true)
        let initialRenderCount = harness.log.renderCount
        harness.publishBattery(increasedBattery)
        let deadline = Date().addingTimeInterval(5)
        while harness.log.renderCount == initialRenderCount, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(harness.log.renderCount > initialRenderCount)
        #expect(harness.log.lastScene != nil)
    }

    private func dockTestBattery(_ percentage: Int, charging: Bool) -> BatteryStatus {
        BatteryStatus(
            rawPercentage: percentage,
            isPresent: true,
            isCharging: charging,
            isLowPowerMode: false,
            isConnectedToPower: charging
        )
    }
}
