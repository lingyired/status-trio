import XCTest
@testable import StatusTrioCore

final class MenuBarRightClickRouterTests: XCTestCase {
    private var allAvailability: [MenuBarQuickActionAvailability] {
        var result: [MenuBarQuickActionAvailability] = []
        for lowPower in [false, true] {
            for charge in [false, true] {
                for mute in [false, true] {
                    result.append(MenuBarQuickActionAvailability(
                        lowPowerMode: lowPower,
                        chargeToFullNow: charge,
                        mute: mute
                    ))
                }
            }
        }
        return result
    }

    func testContextMenuAlwaysShowsContextMenu() {
        for availability in allAvailability {
            XCTAssertEqual(
                MenuBarRightClickRouter.outcome(for: .contextMenu, availability: availability),
                .showContextMenu
            )
        }
    }

    func testEachActionSelectsItsOwnOutcomeWhenAvailable() {
        let available = MenuBarQuickActionAvailability(
            lowPowerMode: true,
            chargeToFullNow: true,
            mute: true
        )

        XCTAssertEqual(
            MenuBarRightClickRouter.outcome(for: .toggleLowPowerMode, availability: available),
            .toggleLowPowerMode
        )
        XCTAssertEqual(
            MenuBarRightClickRouter.outcome(for: .chargeToFullNow, availability: available),
            .toggleChargeToFullNow
        )
        XCTAssertEqual(
            MenuBarRightClickRouter.outcome(for: .toggleMute, availability: available),
            .toggleMute
        )
    }

    func testEachActionFallsBackToContextMenuWhenUnavailable() {
        let unavailable = MenuBarQuickActionAvailability(
            lowPowerMode: false,
            chargeToFullNow: false,
            mute: false
        )

        XCTAssertEqual(
            MenuBarRightClickRouter.outcome(for: .toggleLowPowerMode, availability: unavailable),
            .showContextMenu
        )
        XCTAssertEqual(
            MenuBarRightClickRouter.outcome(for: .chargeToFullNow, availability: unavailable),
            .showContextMenu
        )
        XCTAssertEqual(
            MenuBarRightClickRouter.outcome(for: .toggleMute, availability: unavailable),
            .showContextMenu
        )
    }

    func testAvailabilityOnlyGatesItsOwnAction() {
        // Low power unavailable but the other two available: only the low
        // power action falls back.
        let availability = MenuBarQuickActionAvailability(
            lowPowerMode: false,
            chargeToFullNow: true,
            mute: true
        )
        XCTAssertEqual(
            MenuBarRightClickRouter.outcome(for: .toggleLowPowerMode, availability: availability),
            .showContextMenu
        )
        XCTAssertEqual(
            MenuBarRightClickRouter.outcome(for: .chargeToFullNow, availability: availability),
            .toggleChargeToFullNow
        )
        XCTAssertEqual(
            MenuBarRightClickRouter.outcome(for: .toggleMute, availability: availability),
            .toggleMute
        )
    }

    func testEnumRawValuesRoundTrip() {
        for action in MenuBarRightClickAction.allCases {
            XCTAssertEqual(MenuBarRightClickAction(rawValue: action.rawValue), action)
        }
        XCTAssertNil(MenuBarRightClickAction(rawValue: "not-an-action"))
        XCTAssertEqual(
            MenuBarRightClickAction.allCases.map(\.rawValue),
            ["contextMenu", "toggleLowPowerMode", "chargeToFullNow", "toggleMute"]
        )
    }

    func testEveryActionHasADistinctTitleKey() {
        let keys = MenuBarRightClickAction.allCases.map(\.titleKey)
        XCTAssertEqual(Set(keys).count, MenuBarRightClickAction.allCases.count)
    }
}
