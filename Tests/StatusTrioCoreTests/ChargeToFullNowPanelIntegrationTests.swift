import XCTest
@testable import StatusTrioCore

@MainActor
final class ChargeToFullNowPanelIntegrationTests: XCTestCase {
    func testPanelDemandFollowsSettingVisibilityAndBatterySnapshot() async {
        let backend = PanelChargeBackend(state: .activeLimit)
        let chargeToFullNow = ChargeToFullNowController(backend: backend)
        let fixture = PanelStoreFixture()
        fixture.settings.showsChargeToFullNowButton = true
        let panel = fixture.makePanel(chargeToFullNow: chargeToFullNow)

        panel.start()
        fixture.store.start()
        defer {
            panel.stop()
            fixture.store.stop()
        }

        XCTAssertEqual(panel.chargeToFullNowPresentation, .hidden)
        XCTAssertEqual(backend.readCount, 0)

        fixture.store.setPopoverVisible(true)
        fixture.battery.send(connectedBattery(percentage: 80))
        let debounceStarted = await fixture.popupSleeper.waitForCallCount(1, timeout: .seconds(1))
        XCTAssertTrue(debounceStarted)
        fixture.popupSleeper.releaseAll()

        let becameAvailable = await waitUntil {
            panel.chargeToFullNowPresentation == .available
        }
        XCTAssertTrue(becameAvailable)

        fixture.store.setPopoverVisible(false)
        XCTAssertEqual(panel.chargeToFullNowPresentation, .hidden)

        fixture.store.setPopoverVisible(true)
        fixture.settings.setPopupSection(.battery, enabled: false)
        XCTAssertEqual(panel.chargeToFullNowPresentation, .hidden)
    }

    func testStopClearsTheDemandWithoutAnotherPowerUIRead() {
        let backend = PanelChargeBackend(state: .activeLimit)
        let chargeToFullNow = ChargeToFullNowController(backend: backend)
        let fixture = PanelStoreFixture()
        fixture.settings.showsChargeToFullNowButton = true
        let panel = fixture.makePanel(chargeToFullNow: chargeToFullNow)

        panel.start()
        fixture.store.setPopoverVisible(true)
        let readsBeforeStop = backend.readCount

        panel.stop()

        XCTAssertEqual(panel.chargeToFullNowPresentation, .hidden)
        XCTAssertEqual(backend.readCount, readsBeforeStop)
    }

    func testChargeToFullClickUpdatesTheSummarySubtitleBeforeTheSnapshot() async {
        let backend = PanelChargeBackend(state: .activeLimit)
        let chargeToFullNow = ChargeToFullNowController(backend: backend)
        let fixture = PanelStoreFixture()
        fixture.settings.showsChargeToFullNowButton = true
        let panel = fixture.makePanel(chargeToFullNow: chargeToFullNow)

        panel.start()
        fixture.store.start()
        defer {
            panel.stop()
            fixture.store.stop()
        }

        fixture.store.setPopoverVisible(true)
        fixture.battery.send(BatteryStatus(
            rawPercentage: 80,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: true
        ))
        let debounceStarted = await fixture.popupSleeper.waitForCallCount(1, timeout: .seconds(1))
        XCTAssertTrue(debounceStarted)
        fixture.popupSleeper.releaseAll()
        let becameAvailable = await waitUntil {
            panel.chargeToFullNowPresentation == .available
        }
        XCTAssertTrue(becameAvailable)

        chargeToFullNow.performPrimaryAction()
        XCTAssertEqual(
            panel.battery.subtitle,
            fixture.localization.string(.batteryStateCalculatingTimeToFull)
        )
    }

    private func connectedBattery(percentage: Int) -> BatteryStatus {
        BatteryStatus(
            rawPercentage: percentage,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: true
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }
}

@MainActor
private final class PanelChargeBackend: BatteryChargeControlling {
    let capability: ChargeToFullNowCapability = .available
    var state: ChargeToFullNowDeviceState
    private(set) var readCount = 0

    init(state: ChargeToFullNowDeviceState) {
        self.state = state
    }

    func readState() -> ChargeToFullNowDeviceState {
        readCount += 1
        return state
    }

    func chargeToFullNow() async -> ChargeToFullNowWriteResult {
        .success
    }
}

private extension ChargeToFullNowDeviceState {
    static let activeLimit = ChargeToFullNowDeviceState(
        mclEnabledRawValue: 1,
        mclLimit: 80,
        chargingOverrideAllowed: false
    )
}
