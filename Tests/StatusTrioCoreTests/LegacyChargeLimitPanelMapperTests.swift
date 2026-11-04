import XCTest
@testable import StatusTrioCore

/// The battery details page reuses the controller's state instead of starting a
/// second battery monitor. This mapping decides what the row shows and which
/// single action it offers.
final class LegacyChargeLimitPanelMapperTests: XCTestCase {
    private func state(
        available: Bool = true,
        status: LegacyChargeLimitStatus,
        selectedLimit: Int? = 90,
        isApplying: Bool = false
    ) -> LegacyChargeLimitPanelState {
        LegacyChargeLimitPanelMapper.map(
            availability: available
                ? .available(.intelBCLM)
                : .unavailable(.unsupportedOS),
            status: status,
            selectedLimit: selectedLimit,
            isApplying: isApplying
        )
    }

    func testUnavailableControllerShowsNoRow() {
        let mapped = state(available: false, status: .notEnabled)
        XCTAssertFalse(mapped.isVisible)
    }

    func testNotEnabledShowsNoRow() {
        let mapped = state(status: .notEnabled, selectedLimit: nil)
        XCTAssertFalse(mapped.isVisible, "The panel is not a settings surface; stay out of the way")
    }

    func testHoldingOffersTemporaryFullCharge() {
        let mapped = state(status: .holding(at: 90))
        XCTAssertTrue(mapped.isVisible)
        XCTAssertEqual(mapped.status, .holding(90))
        XCTAssertEqual(mapped.action, .chargeToFull)
        XCTAssertFalse(mapped.isBusy)
    }

    func testTemporaryFullOffersCancel() {
        let mapped = state(status: .temporarilyChargingToFull)
        XCTAssertEqual(mapped.status, .temporarilyFull)
        XCTAssertEqual(mapped.action, .cancelFullCharge)
        XCTAssertEqual(mapped.targetLimit, 90, "Temporary full must keep the intended restore ceiling visible")
    }

    func testBusyAndFailedRowsRetainTheSelectedTarget() {
        let busy = state(status: .holding(at: 90), isApplying: true)
        XCTAssertEqual(busy.targetLimit, 90)
        XCTAssertEqual(busy.action, .none)
        XCTAssertEqual(state(status: .restoreFailed, selectedLimit: 85).targetLimit, 85)
        XCTAssertNil(state(status: .notEnabled, selectedLimit: nil).targetLimit)
    }

    func testApplyingDisablesTheActionAndShowsBusy() {
        let mapped = state(status: .holding(at: 90), isApplying: true)
        XCTAssertTrue(mapped.isBusy)
        XCTAssertEqual(mapped.action, .none)
    }

    func testFailureKeepsTheRowVisibleWithNoAction() {
        XCTAssertEqual(state(status: .externalChange).status, .externalChange)
        XCTAssertEqual(state(status: .failed).action, .none)
        XCTAssertEqual(state(status: .restoreFailed).action, .none)
        XCTAssertEqual(state(status: .unverified).action, .none)
    }

    func testRecoveryEntryAppearsOnlyWhenTheCapIsUncertain() {
        XCTAssertTrue(LegacyChargeLimitRecovery.showsRestoreAction(status: .restoreFailed))
        XCTAssertTrue(LegacyChargeLimitRecovery.showsRestoreAction(status: .unverified))
        XCTAssertTrue(LegacyChargeLimitRecovery.showsRestoreAction(status: .externalChange))
        XCTAssertTrue(LegacyChargeLimitRecovery.showsRestoreAction(status: .failed))
        XCTAssertFalse(LegacyChargeLimitRecovery.showsRestoreAction(status: .notEnabled))
        XCTAssertFalse(LegacyChargeLimitRecovery.showsRestoreAction(status: .holding(at: 80)))
        XCTAssertFalse(LegacyChargeLimitRecovery.showsRestoreAction(status: .temporarilyChargingToFull))
        XCTAssertFalse(LegacyChargeLimitRecovery.showsRestoreAction(status: .checkingHardware))
    }

    func testUnsupportedShowsNoRow() {
        XCTAssertFalse(state(status: .unsupported, selectedLimit: nil).isVisible)
    }
}