import XCTest
@testable import StatusTrioCore

final class MenuBarRightClickRouterTests: XCTestCase {
    private func availability(
        lowPowerMode: Bool = true,
        chargeToFullNow: Bool = true,
        mute: Bool = true,
        wifi: Bool = true
    ) -> MenuBarQuickActionAvailability {
        MenuBarQuickActionAvailability(
            lowPowerMode: lowPowerMode,
            chargeToFullNow: chargeToFullNow,
            mute: mute,
            wifi: wifi
        )
    }

    private var allAvailability: [MenuBarQuickActionAvailability] {
        var result: [MenuBarQuickActionAvailability] = []
        for lowPower in [false, true] {
            for charge in [false, true] {
                for mute in [false, true] {
                    for wifi in [false, true] {
                        result.append(availability(
                            lowPowerMode: lowPower,
                            chargeToFullNow: charge,
                            mute: mute,
                            wifi: wifi
                        ))
                    }
                }
            }
        }
        return result
    }

    /// The capability-gated actions and the outcome each maps to when available.
    private let capabilityActions: [(MenuBarRightClickAction, MenuBarRightClickOutcome)] = [
        (.toggleLowPowerMode, .toggleLowPowerMode),
        (.chargeToFullNow, .toggleChargeToFullNow),
        (.toggleMute, .toggleMute),
        (.toggleWiFi, .toggleWiFi)
    ]

    /// Actions with no runtime precondition; they map directly to their outcome.
    private let alwaysAvailableActions: [(MenuBarRightClickAction, MenuBarRightClickOutcome)] = [
        (.refreshStatus, .refreshStatus),
        (.openWiFiSettings, .openWiFiSettings),
        (.openBluetoothSettings, .openBluetoothSettings),
        (.openBatterySettings, .openBatterySettings),
        (.openSoundSettings, .openSoundSettings)
    ]

    func testContextMenuAlwaysShowsContextMenu() {
        for availability in allAvailability {
            XCTAssertEqual(
                MenuBarRightClickRouter.outcome(for: .contextMenu, availability: availability),
                .showContextMenu
            )
        }
    }

    func testEachActionSelectsItsOwnOutcomeWhenAvailable() {
        let available = availability()
        for (action, outcome) in capabilityActions + alwaysAvailableActions {
            XCTAssertEqual(
                MenuBarRightClickRouter.outcome(for: action, availability: available),
                outcome,
                "\(action) should map to \(outcome) when available"
            )
        }
    }

    func testCapabilityActionsFallBackToContextMenuWhenUnavailable() {
        let unavailable = availability(
            lowPowerMode: false,
            chargeToFullNow: false,
            mute: false,
            wifi: false
        )
        for (action, _) in capabilityActions {
            XCTAssertEqual(
                MenuBarRightClickRouter.outcome(for: action, availability: unavailable),
                .showContextMenu,
                "\(action) should fall back when unavailable"
            )
        }
    }

    func testAlwaysAvailableActionsNeverFallBack() {
        let unavailable = availability(
            lowPowerMode: false,
            chargeToFullNow: false,
            mute: false,
            wifi: false
        )
        for (action, outcome) in alwaysAvailableActions {
            XCTAssertEqual(
                MenuBarRightClickRouter.outcome(for: action, availability: unavailable),
                outcome,
                "\(action) should stay available regardless of capability flags"
            )
        }
    }

    func testOneUnavailableCapabilityOnlyGatesItsOwnAction() {
        let availability = availability(
            lowPowerMode: false,
            chargeToFullNow: true,
            mute: true,
            wifi: true
        )
        XCTAssertEqual(
            MenuBarRightClickRouter.outcome(for: .toggleLowPowerMode, availability: availability),
            .showContextMenu
        )
        XCTAssertEqual(
            MenuBarRightClickRouter.outcome(for: .toggleWiFi, availability: availability),
            .toggleWiFi
        )
        XCTAssertEqual(
            MenuBarRightClickRouter.outcome(for: .refreshStatus, availability: availability),
            .refreshStatus
        )
    }

    func testEnumRawValuesRoundTrip() {
        for action in MenuBarRightClickAction.allCases {
            XCTAssertEqual(MenuBarRightClickAction(rawValue: action.rawValue), action)
        }
        XCTAssertNil(MenuBarRightClickAction(rawValue: "not-an-action"))
        XCTAssertEqual(
            MenuBarRightClickAction.allCases.map(\.rawValue),
            [
                "contextMenu",
                "toggleLowPowerMode",
                "chargeToFullNow",
                "toggleMute",
                "toggleWiFi",
                "refreshStatus",
                "openWiFiSettings",
                "openBluetoothSettings",
                "openBatterySettings",
                "openSoundSettings"
            ]
        )
    }

    func testEveryActionHasADistinctTitleKey() {
        let keys = MenuBarRightClickAction.allCases.map(\.titleKey)
        XCTAssertEqual(Set(keys).count, MenuBarRightClickAction.allCases.count)
    }
}
