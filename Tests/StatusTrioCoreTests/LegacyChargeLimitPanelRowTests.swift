import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

private final class PanelFakeClient: LegacyChargeLimitClienting, @unchecked Sendable {
    var probe: Result<LegacyChargeLimitProbeFacts, any Error> = .success(
        LegacyChargeLimitProbeFacts(
            hasInternalBattery: true,
            intelBCLMPresent: true,
            siliconPairPresent: false,
            siliconCHTEPresent: false
        )
    )
    var setLimitResult: Result<LegacyChargeLimitWriteOutcome, any Error> = .success(.success)
    var chargeToFullResult: Result<LegacyChargeLimitWriteOutcome, any Error> = .success(.success)
    var cancelResult: Result<LegacyChargeLimitWriteOutcome, any Error> = .success(.success)

    func probe() async throws -> LegacyChargeLimitProbeFacts { try probe.get() }
    func setLimit(_ limit: Int, expectedLimit: Int?) async throws -> LegacyChargeLimitWriteOutcome {
        try setLimitResult.get()
    }
    func chargeToFullOnce() async throws -> LegacyChargeLimitWriteOutcome { try chargeToFullResult.get() }
    func cancelChargeToFull() async throws -> LegacyChargeLimitWriteOutcome { try cancelResult.get() }
    func disable(expectedLimit: Int?) async throws -> LegacyChargeLimitWriteOutcome { .success }
    func verify(_ limit: Int) async throws -> LegacyChargeLimitWriteOutcome { .success }
    func prepareForSleep() async throws -> LegacyChargeLimitWriteOutcome { .success }
}

/// The panel row must render inside the popover width in every language and
/// must disappear when the feature is not active. This hosts the real view; no
/// window is ordered and no status item is created.
@MainActor
final class LegacyChargeLimitPanelRowTests: XCTestCase {
    private func makeController() -> LegacyChargeLimitController {
        LegacyChargeLimitController(
            client: PanelFakeClient(),
            sessionStore: VolatileLegacyChargeLimitSessionStore(),
            architecture: .intel,
            osBand: .thirteenToFourteen
        )
    }

    private func makeLocalization(_ language: AppLanguage) -> Localization {
        let suiteName = "LegacyChargeLimitPanelRowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { TestUserDefaults.removeSuite(named: suiteName) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(language))
        return localization
    }

    private func hostingHeight(
        _ controller: LegacyChargeLimitController,
        language: AppLanguage
    ) -> CGFloat {
        let root = LocalizedRootView(localization: makeLocalization(language)) {
            LegacyChargeLimitPanelRow(controller: controller)
        }
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 330, height: 120)
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.height
    }

    func testRowIsAbsentWhenTheFeatureIsNotActive() async {
        let controller = makeController()
        await controller.refresh()
        for language in AppLanguage.allCases {
            XCTAssertEqual(hostingHeight(controller, language: language), 0, language.rawValue)
        }
    }

    func testHoldingRowRendersInEveryLanguageWithinThePopoverWidth() async {
        let controller = makeController()
        await controller.refresh()
        _ = await controller.setLimit(80)
        for language in AppLanguage.allCases {
            let height = hostingHeight(controller, language: language)
            XCTAssertGreaterThan(height, 0, "\(language.rawValue) rendered no row")
            XCTAssertLessThan(height, 80, "\(language.rawValue) row is taller than its content")
        }
    }

    func testTemporaryFullRowRenders() async {
        let controller = makeController()
        await controller.refresh()
        _ = await controller.setLimit(80)
        _ = await controller.chargeToFullOnce()
        XCTAssertGreaterThan(hostingHeight(controller, language: .simplifiedChinese), 0)
    }
}