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

    func testMainBatteryCardIncludesTheHeldLimitAndFullChargeState() async {
        let controller = makeController()
        await controller.refresh()
        let withoutRow = summarySize(nil, language: .simplifiedChinese)
        let disabled = summarySize(controller, language: .simplifiedChinese)
        XCTAssertEqual(disabled.height, withoutRow.height, accuracy: 1)
        _ = await controller.setLimit(90)
        for language in AppLanguage.allCases {
            let held = summarySize(controller, language: language)
            let plain = summarySize(nil, language: language)
            XCTAssertGreaterThan(held.height, plain.height + 15, language.rawValue)
            XCTAssertLessThanOrEqual(held.width, 332, language.rawValue)
        }
        _ = await controller.chargeToFullOnce()
        XCTAssertGreaterThan(summarySize(controller, language: .simplifiedChinese).height,
                             withoutRow.height + 15)
    }

    func testMainCardCanHideQuickActionsWithoutHidingTheCeiling() async {
        let controller = makeController()
        await controller.refresh()
        _ = await controller.setLimit(85)
        let card = summary(controller, language: .english, showsActions: false)
        XCTAssertFalse(card.showsLegacyChargeActions)
        let hosting = NSHostingView(rootView: card.environmentObject(makeLocalization(.english)))
        hosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(hosting.fittingSize.height, summarySize(nil, language: .english).height)
    }

    private func summary(
        _ controller: LegacyChargeLimitController?, language: AppLanguage, showsActions: Bool = true
    ) -> BatteryStatusView {
        let status = BatteryStatus(rawPercentage: 78, isPresent: true, isCharging: false,
                                   isLowPowerMode: false, isConnectedToPower: true)
        return BatteryStatusView(
            state: PanelPresentationMapper.battery(status, localization: makeLocalization(language)),
            onOpenBatteryDetails: {}, onOpenBatterySettings: {},
            legacyChargeLimit: controller, showsLegacyChargeActions: showsActions
        )
    }

    private func summarySize(
        _ controller: LegacyChargeLimitController?, language: AppLanguage
    ) -> NSSize {
        let hosting = NSHostingView(rootView: summary(controller, language: language)
            .environmentObject(makeLocalization(language)).frame(width: 330))
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize
    }

    /// Opt-in visual previews, same convention as the battery details layout
    /// tests: set STATUS_TRIO_BATTERY_SNAPSHOTS to a directory to write PNGs.
    func testWritesOptInBatteryPanelSnapshots() async throws {
        guard let raw = ProcessInfo.processInfo.environment["STATUS_TRIO_BATTERY_SNAPSHOTS"] else {
            throw XCTSkip("Set STATUS_TRIO_BATTERY_SNAPSHOTS to write panel previews")
        }
        let directory = URL(fileURLWithPath: raw, isDirectory: true)
        let controller = makeController()
        await controller.refresh()
        _ = await controller.setLimit(85)
        for language in [AppLanguage.english, .simplifiedChinese, .german] {
            try writeSnapshot(
                summary(controller, language: language)
                    .environmentObject(makeLocalization(language))
                    .frame(width: 330)
                    .padding(14)
                    .background(Color(nsColor: .windowBackgroundColor)),
                to: directory.appendingPathComponent("summary-holding-\(language.rawValue).png")
            )
            _ = await controller.chargeToFullOnce()
            try writeSnapshot(
                summary(controller, language: language)
                    .environmentObject(makeLocalization(language))
                    .frame(width: 330)
                    .padding(14)
                    .background(Color(nsColor: .windowBackgroundColor)),
                to: directory.appendingPathComponent("summary-temporary-full-\(language.rawValue).png")
            )
            _ = await controller.cancelChargeToFull()
        }

        // The details page reuses the same row; capture it in context.
        _ = await controller.setLimit(85)
        for language in [AppLanguage.english, .simplifiedChinese] {
            try writeSnapshot(
                BatteryDetailsView(
                    state: detailsState(language),
                    onBack: {},
                    onOpenBatterySettings: {},
                    onCopyValue: { _ in },
                    onAppear: {},
                    legacyChargeLimit: controller
                )
                .padding(14)
                .frame(width: 330)
                .background(Color(nsColor: .windowBackgroundColor))
                .environmentObject(makeLocalization(language)),
                to: directory.appendingPathComponent("details-holding-\(language.rawValue).png")
            )
        }
    }

    private func detailsState(_ language: AppLanguage) -> PanelDetailState {
        let localization = makeLocalization(language)
        return PanelDetailState(
            title: localization.string(.batteryDetailsTitle),
            rows: [
                PanelDetailRow(
                    id: "cycle", label: "Cycle Count", value: "120",
                    accessibilityValue: "120", tint: .secondary
                ),
                PanelDetailRow(
                    id: "health", label: "Condition", value: "Normal",
                    accessibilityValue: "Normal", tint: .positive
                ),
            ],
            isLoading: false,
            errorText: nil,
            explanation: nil
        )
    }

    private func writeSnapshot(_ view: some View, to url: URL) throws {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try png.write(to: url)
    }
}