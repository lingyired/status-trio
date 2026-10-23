import AppKit
import Testing
@testable import StatusTrioCore

@Suite(.serialized)
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
        let snapshotScheduler = ManualIconPresentationScheduler()
        let harness = try AppIconControllerHarness(
            initialPlacement: .dock,
            initialBattery: dockTestBattery(60, charging: true),
            snapshotScheduler: snapshotScheduler
        )
        harness.controller.start()
        defer {
            harness.controller.stop()
            harness.cleanUp()
        }

        let increasedBattery = dockTestBattery(61, charging: true)
        let initialRenderCount = harness.log.renderCount
        harness.publishBattery(increasedBattery)
        try await waitForStoreBattery(increasedBattery, in: harness)
        try #require(
            snapshotScheduler.hasPendingAction,
            "The battery update must schedule the presentation debounce."
        )
        snapshotScheduler.runScheduled()
        #expect(harness.iconPresentation.output.scene.outerRing?.segments.first?.progress == 0.61)
        harness.controller.flushPendingPresentationForTesting()

        #expect(harness.log.renderCount > initialRenderCount)
        #expect(harness.log.lastScene != nil)
    }

    private func waitForStoreBattery(
        _ battery: BatteryStatus,
        in harness: AppIconControllerHarness
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if harness.store.snapshot.battery == battery { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw ChargingEffectControllerTestFailure.batteryDidNotReachStore(
            expected: battery,
            actual: harness.store.snapshot.battery,
            snapshot: harness.store.snapshot,
            batteryProgressInModel: harness.iconPresentation.output.scene.outerRing?.segments.first?.progress,
            latestScene: harness.iconPresentation.output.scene,
            renderCount: harness.log.renderCount,
            lastRenderedScene: harness.log.lastScene
        )
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

private enum ChargingEffectControllerTestFailure: Error, CustomStringConvertible {
    case batteryDidNotReachStore(
        expected: BatteryStatus,
        actual: BatteryStatus,
        snapshot: StatusSnapshot,
        batteryProgressInModel: Double?,
        latestScene: IconSceneState,
        renderCount: Int,
        lastRenderedScene: IconSceneState?
    )

    var description: String {
        switch self {
        case let .batteryDidNotReachStore(
            expected,
            actual,
            snapshot,
            batteryProgressInModel,
            latestScene,
            renderCount,
            lastRenderedScene
        ):
            """
            The battery update did not reach the status store.
              expected battery: \(expected)
              actual battery: \(actual)
              snapshot: \(snapshot)
              battery progress in model: \(batteryProgressInModel.map { String($0) } ?? "none")
              latest model scene: \(latestScene)
              delivered scene: \(String(describing: lastRenderedScene))
              render count: \(renderCount)
              elapsed: 5.0s
            """
        }
    }
}
