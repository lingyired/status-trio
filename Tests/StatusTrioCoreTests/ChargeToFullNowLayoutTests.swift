import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class ChargeToFullNowLayoutTests: XCTestCase {
    func testAvailableButtonAddsASeparateRowBelowTheBatterySummary() throws {
        let hidden = try render(.hidden)
        let available = try render(.available)

        XCTAssertEqual(hidden.width, 330, accuracy: 1)
        XCTAssertEqual(available.width, 330, accuracy: 1)
        XCTAssertGreaterThan(available.height, hidden.height + 20)
    }

    func testApplyingAndFailureStatesRemainInsideThePopoverWidth() throws {
        for presentation in [
            ChargeToFullNowPresentation.applying,
            .chargingToFull,
            .failed,
            .unavailable,
            .cancelConfirmationRequired(limit: 80, usedFallback: false),
            .cancelPending,
            .cancelling,
            .cancelFailed(message: "PowerUI rejected the request."),
            .cancelSucceeded(limit: 80, usedFallback: false)
        ] {
            let size = try render(presentation)
            XCTAssertEqual(size.width, 330, accuracy: 1)
            XCTAssertLessThan(size.height, 190)
        }
    }

    func testChargingStatusAndCancelShareTheActionButtonRow() throws {
        let available = try render(.available)
        let charging = try render(.chargingToFull)

        XCTAssertEqual(charging.width, 330, accuracy: 1)
        XCTAssertEqual(charging.height, available.height, accuracy: 1)
    }

    func testEverySupportedLanguageFitsThePopoverForAllButtonStates() throws {
        XCTAssertEqual(AppLanguage.allCases.count, 12)

        for language in AppLanguage.allCases {
            for presentation in [
                ChargeToFullNowPresentation.available,
                .applying,
                .chargingToFull,
                .failed,
                .unavailable,
                .cancelConfirmationRequired(limit: 80, usedFallback: false),
                .cancelConfirmationRequired(limit: 80, usedFallback: true),
                .cancelPending,
                .cancelling,
                .cancelFailed(message: "PowerUI rejected the request."),
                .cancelSucceeded(limit: 80, usedFallback: false),
                .cancelSucceeded(limit: 80, usedFallback: true)
            ] {
                let size = try render(presentation, language: language)
                XCTAssertEqual(
                    size.width,
                    330,
                    accuracy: 1,
                    "\(language.rawValue) must keep the fixed popover width"
                )
                XCTAssertLessThan(
                    size.height,
                    220,
                    "\(language.rawValue) produced an unexpectedly tall \(presentation) row"
                )
            }
        }
    }

    private func render(
        _ presentation: ChargeToFullNowPresentation,
        language: AppLanguage = .english
    ) throws -> NSSize {
        let suite = "StatusTrioCoreTests.ChargeToFullNowLayout.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(
            defaults: defaults,
            preferredLanguages: [language.rawValue]
        )
        let battery = BatteryStatus(
            rawPercentage: 80,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: true
        )
        let view = BatteryStatusView(
            state: PanelPresentationMapper.battery(battery, localization: localization),
            cautionColor: .yellow,
            onOpenBatteryDetails: {},
            onOpenBatterySettings: {},
            chargeToFullNow: presentation,
            onChargeToFullNow: {}
        )
        .padding(14)
        .frame(width: 330)
        .background(Color(white: 0.96))
        .environmentObject(localization)
        .environment(\.layoutDirection, language.layoutDirection)
        .environment(\.colorScheme, .light)

        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize
    }
}
