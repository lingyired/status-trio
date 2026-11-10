import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class ChargeToFullNowDiagnosticsTests: XCTestCase {
    func testUnsupportedCapabilitiesDoNotReadBackend() {
        let cases: [(ChargeToFullNowUnavailableReason, ChargeToFullNowHiddenReason)] = [
            (.unsupportedSystem, .unsupportedSystem),
            (.unsupportedArchitecture, .unsupportedArchitecture),
            (.frameworkUnavailable, .frameworkUnavailable),
            (.apiUnavailable, .apiUnavailable),
            (.mclUnsupported, .mclUnsupported)
        ]
        for (capability, expected) in cases {
            let backend = DiagnosticsStubChargeController(
                capability: .unavailable(capability),
                deviceState: .activeLimit
            )
            let controller = ChargeToFullNowController(backend: backend)
            XCTAssertEqual(
                controller.hiddenReasons(battery: battery(), batterySectionVisible: true),
                [expected]
            )
            XCTAssertEqual(backend.readCount, 0)
        }
    }

    func testLiveBlockersAccumulateWithoutReadingAndAbsentBatteryHasNoPowerBlockers() {
        let backend = DiagnosticsStubChargeController(deviceState: .activeLimit)
        let controller = ChargeToFullNowController(backend: backend)

        XCTAssertEqual(
            controller.hiddenReasons(
                battery: battery(connected: false, percentage: 100),
                batterySectionVisible: false
            ),
            [.batterySectionHidden, .disconnectedFromPower, .fullyCharged]
        )
        XCTAssertEqual(
            controller.hiddenReasons(
                battery: battery(present: false, connected: false, percentage: 100),
                batterySectionVisible: false
            ),
            [.noBattery, .batterySectionHidden]
        )
        XCTAssertEqual(backend.readCount, 0)
    }

    func testFreshStateOverridesCachedAvailableAndErrorsTakePriority() {
        let backend = DiagnosticsStubChargeController(deviceState: .activeLimit)
        let controller = ChargeToFullNowController(backend: backend)
        controller.update(demand())
        XCTAssertEqual(controller.presentation, .available)
        XCTAssertEqual(
            controller.hiddenReasons(battery: battery(), batterySectionVisible: true),
            []
        )

        backend.deviceState = .disabled
        XCTAssertEqual(
            controller.hiddenReasons(battery: battery(), batterySectionVisible: true),
            []
        )
        backend.deviceState = state(raw: 1, limit: 82)
        XCTAssertEqual(
            controller.hiddenReasons(battery: battery(), batterySectionVisible: true),
            [.unrecognizedChargeLimitState]
        )
        backend.deviceState = state(raw: 9, limit: 80)
        XCTAssertEqual(
            controller.hiddenReasons(battery: battery(), batterySectionVisible: true),
            [.unrecognizedChargeLimitState]
        )
        backend.deviceState = .unavailable
        XCTAssertEqual(
            controller.hiddenReasons(battery: battery(), batterySectionVisible: true),
            [.stateReadFailed]
        )
        // Reading diagnostics never writes or mutates the controller.
        XCTAssertEqual(backend.writeCount, 0)
        XCTAssertEqual(backend.restoreCount, 0)
        XCTAssertEqual(controller.presentation, .available)
    }

    func testSessionAndNativeOverrideDoNotReportMissingLimit() {
        let backend = DiagnosticsStubChargeController(deviceState: .temporaryOverride)
        let controller = ChargeToFullNowController(backend: backend)
        XCTAssertEqual(
            controller.hiddenReasons(battery: battery(), batterySectionVisible: true),
            []
        )

        backend.deviceState = .disabled
        let store = VolatileChargeToFullNowSessionStore(
            session: ChargeToFullNowSession(originalLimit: 80, acceptedAt: Date())
        )
        let sessionController = ChargeToFullNowController(
            backend: backend,
            sessionStore: store
        )
        XCTAssertEqual(
            sessionController.hiddenReasons(
                battery: battery(),
                batterySectionVisible: true
            ),
            []
        )
        XCTAssertNotNil(store.load())
    }

    func testApplyingDoesNotReadTransientMissingLimit() async {
        let backend = DiagnosticsStubChargeController(deviceState: .activeLimit)
        let controller = ChargeToFullNowController(backend: backend)
        controller.update(demand())
        controller.performPrimaryAction()
        XCTAssertEqual(controller.presentation, .applying)

        backend.deviceState = .disabled
        let reads = backend.readCount
        XCTAssertEqual(
            controller.hiddenReasons(battery: battery(), batterySectionVisible: true),
            []
        )
        XCTAssertEqual(backend.readCount, reads)
        backend.finishWrite(.success)
        for _ in 0..<20 { await Task.yield() }
    }

    func testRestoreReturnsStraightToTheActionWithoutHiddenReason() async {
        let backend = DiagnosticsStubChargeController(deviceState: .temporaryOverride)
        backend.restoreState = state(raw: 1, limit: 90)
        let store = VolatileChargeToFullNowSessionStore(
            session: ChargeToFullNowSession(originalLimit: 90, acceptedAt: Date())
        )
        let controller = ChargeToFullNowController(
            backend: backend,
            sessionStore: store,
            restoreLimit: { 90 }
        )
        controller.update(demand())
        XCTAssertEqual(controller.presentation, .chargingToFull)

        controller.performPrimaryAction()
        XCTAssertEqual(
            controller.presentation,
            .cancelConfirmationRequired(limit: 90)
        )
        controller.performPrimaryAction()
        for _ in 0..<100 {
            if controller.presentation == .available { break }
            await Task.yield()
        }
        // The restore-limit feature is off: after a verified restore the action
        // follows the live state again, so Settings has nothing to explain.
        XCTAssertEqual(controller.presentation, .available)
        XCTAssertEqual(
            controller.hiddenReasons(battery: battery(), batterySectionVisible: true),
            []
        )

        backend.deviceState = .unavailable
        XCTAssertEqual(
            controller.hiddenReasons(battery: battery(), batterySectionVisible: true),
            [.stateReadFailed]
        )
    }

    func testPausedChargeWithoutNativeLimitHasNoHiddenReason() {
        // #292: a paused charge with no sub-100% native limit now offers the
        // action, so Settings must not claim a missing limit.
        let backend = DiagnosticsStubChargeController(deviceState: .overridablePause)
        let controller = ChargeToFullNowController(backend: backend)

        XCTAssertEqual(
            controller.hiddenReasons(
                battery: battery(isCharging: false),
                batterySectionVisible: true
            ),
            []
        )
    }

    func testNonOverridablePauseReportsAnOverridableReason() {
        let backend = DiagnosticsStubChargeController(deviceState: .disabled)
        let controller = ChargeToFullNowController(backend: backend)

        XCTAssertEqual(
            controller.hiddenReasons(
                battery: battery(isCharging: false),
                batterySectionVisible: true
            ),
            [.unrecognizedChargeLimitState]
        )
    }

    func testChargingNormallyWithoutNativeLimitHasNoHiddenReason() {
        let backend = DiagnosticsStubChargeController(deviceState: .disabled)
        let controller = ChargeToFullNowController(backend: backend)

        XCTAssertEqual(
            controller.hiddenReasons(
                battery: battery(isCharging: true),
                batterySectionVisible: true
            ),
            []
        )
    }

    private func state(raw: UInt, limit: Int?) -> ChargeToFullNowDeviceState {
        ChargeToFullNowDeviceState(
            mclEnabledRawValue: raw,
            mclLimit: limit,
            chargingOverrideAllowed: false
        )
    }

    private func battery(
        present: Bool = true,
        connected: Bool = true,
        percentage: Int = 60,
        isCharging: Bool = true
    ) -> BatteryStatus {
        BatteryStatus(
            rawPercentage: percentage,
            isPresent: present,
            isCharging: isCharging,
            isCharged: false,
            isLowPowerMode: false,
            isConnectedToPower: connected
        )
    }

    private func demand() -> ChargeToFullNowDemand {
        ChargeToFullNowDemand(
            popoverVisible: true,
            batterySectionVisible: true,
            battery: battery()
        )
    }
}

private final class DiagnosticsStubChargeController: BatteryChargeControlling {
    let capability: ChargeToFullNowCapability
    var deviceState: ChargeToFullNowDeviceState
    var restoreState: ChargeToFullNowDeviceState?
    var restoreResult = ChargeToFullNowWriteResult.success
    private(set) var readCount = 0
    private(set) var writeCount = 0
    private(set) var restoreCount = 0
    private var writeContinuation: CheckedContinuation<ChargeToFullNowWriteResult, Never>?

    init(
        capability: ChargeToFullNowCapability = .available,
        deviceState: ChargeToFullNowDeviceState
    ) {
        self.capability = capability
        self.deviceState = deviceState
    }

    func readState() -> ChargeToFullNowDeviceState {
        readCount += 1
        return deviceState
    }

    func chargeToFullNow() async -> ChargeToFullNowWriteResult {
        writeCount += 1
        return await withCheckedContinuation { continuation in
            writeContinuation = continuation
        }
    }

    func finishWrite(_ result: ChargeToFullNowWriteResult) {
        writeContinuation?.resume(returning: result)
        writeContinuation = nil
    }

    func restoreChargeLimit(
        to limit: Int,
        expectedLimit: Int?
    ) async -> ChargeToFullNowWriteResult {
        restoreCount += 1
        if let restoreState {
            deviceState = restoreState
        }
        return restoreResult
    }
}

private extension ChargeToFullNowDeviceState {
    static let activeLimit = ChargeToFullNowDeviceState(
        mclEnabledRawValue: 1,
        mclLimit: 80,
        chargingOverrideAllowed: false
    )

    static let disabled = ChargeToFullNowDeviceState(
        mclEnabledRawValue: 0,
        mclLimit: 80,
        chargingOverrideAllowed: false
    )

    /// Optimized Battery Charging paused with no sub-100% limit; the system
    /// reports the pause as overridable.
    static let overridablePause = ChargeToFullNowDeviceState(
        mclEnabledRawValue: 0,
        mclLimit: 100,
        chargingOverrideAllowed: true
    )

    static let temporaryOverride = ChargeToFullNowDeviceState(
        mclEnabledRawValue: 3,
        mclLimit: nil,
        chargingOverrideAllowed: true
    )

    static let unavailable = ChargeToFullNowDeviceState(
        mclEnabledRawValue: 0,
        mclLimit: nil,
        chargingOverrideAllowed: false,
        errorMessage: "read failed"
    )
}
