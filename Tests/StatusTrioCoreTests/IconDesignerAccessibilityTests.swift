import XCTest
@testable import StatusTrioCore

final class IconDesignerAccessibilityTests: XCTestCase {
    func testResolutionExplanationLocalizesRoleAndUnavailableReasonWithoutSourceIdentity() {
        let trace = SlotResolutionTrace(
            selectedSourceID: "bluetooth:AA:BB:CC:DD:EE:FF",
            role: .fallback,
            primaryFailure: .permissionDenied,
            reason: .fallback(.permissionDenied)
        )

        let explanation = IconResolutionExplanation.localizationKeys(for: trace)

        XCTAssertEqual(explanation, [.iconResolutionFallback, .iconResolutionUnavailablePermissionDenied])
        XCTAssertFalse(explanation.map(\.rawValue).joined(separator: " ").contains("AA:BB"))
    }

    func testResolutionExplanationShowsPermissionWhenLiveBluetoothFallbackIsBlocked() {
        let trace = SlotResolutionTrace(
            selectedSourceID: "connectedBluetoothDevice:AA:BB:CC:DD:EE:FF",
            role: .fallback,
            primaryFailure: .permissionDenied,
            reason: .fallback(.disconnected)
        )

        let entry = IconResolutionExplanation.entries(
            for: IconResolutionTrace(outerRing: .empty, center: trace, footer: .empty),
            permissionBlockedSlots: [.center]
        )[1]
        XCTAssertEqual(entry.reasonKeys, [.iconResolutionFallback, .iconResolutionUnavailablePermissionDenied])
    }

    func testBluetoothFallbackExplanationDistinguishesUnrequestedAndDeniedPermission() {
        let fallback = SlotResolutionTrace(
            selectedSourceID: "automaticLegacy",
            role: .fallback,
            primaryFailure: .disconnected,
            reason: .fallback(.disconnected)
        )
        let trace = IconResolutionTrace(outerRing: .empty, center: fallback, footer: .empty)
        let cases: [(BluetoothAuthorizationStatus, LocalizationKey)] = [
            (.notDetermined, .settingsBluetoothPermissionRequired),
            (.denied, .iconResolutionUnavailablePermissionDenied),
            (.restricted, .iconResolutionUnavailablePermissionDenied)
        ]

        for (authorization, expectedReason) in cases {
            let entry = IconResolutionExplanation.entries(
                for: trace,
                permissionBlockedSlots: [.center],
                bluetoothAuthorization: authorization
            )[1]
            XCTAssertEqual(entry.reasonKeys, [.iconResolutionFallback, expectedReason])
        }
    }

    func testBluetoothPermissionNoticeActionMatchesAuthorizationState() {
        XCTAssertEqual(BluetoothPermissionNoticeAction(authorization: .notDetermined), .requestAuthorization)
        XCTAssertEqual(BluetoothPermissionNoticeAction(authorization: .denied), .openPermissionSettings)
        XCTAssertEqual(BluetoothPermissionNoticeAction(authorization: .restricted), .openPermissionSettings)
        XCTAssertNil(BluetoothPermissionNoticeAction(authorization: .allowed))
    }

    func testBluetoothPermissionFallbackNoticeIsLiveOnlyAndTracksTheConfiguredPrimary() {
        var configuration = IconConfigurationV1.classic
        configuration.composition.center.primary = .connectedBluetoothDevice
        let trace = IconResolutionTrace(
            outerRing: .empty,
            center: SlotResolutionTrace(
                selectedSourceID: "automaticLegacy",
                role: .fallback,
                primaryFailure: .disconnected,
                reason: .fallback(.disconnected)
            ),
            footer: .empty
        )

        XCTAssertEqual(
            IconResolutionExplanation.permissionBlockedBluetoothFallbackSlots(
                configuration: configuration,
                trace: trace,
                authorization: .denied,
                scenario: .live
            ),
            [.center]
        )
        XCTAssertTrue(IconResolutionExplanation.permissionBlockedBluetoothFallbackSlots(
            configuration: configuration,
            trace: trace,
            authorization: .denied,
            scenario: .airPodsConnected
        ).isEmpty)
        XCTAssertTrue(IconResolutionExplanation.permissionBlockedBluetoothFallbackSlots(
            configuration: configuration,
            trace: trace,
            authorization: .allowed,
            scenario: .live
        ).isEmpty)
    }

    func testResolutionExplanationCoversPrimaryOverrideAndNone() {
        XCTAssertEqual(
            IconResolutionExplanation.localizationKeys(for: SlotResolutionTrace(
                selectedSourceID: "network", role: .primary, primaryFailure: nil, reason: .primary
            )),
            [.iconResolutionPrimary]
        )
        XCTAssertEqual(
            IconResolutionExplanation.localizationKeys(for: SlotResolutionTrace(
                selectedSourceID: "network", role: .primary, primaryFailure: nil,
                reason: .overridden(.networkProblem)
            )),
            [.iconResolutionOverriddenNetworkProblem]
        )
        XCTAssertEqual(IconResolutionExplanation.localizationKeys(for: .empty), [.iconResolutionNone])
    }

    func testDesignerSlotPickerAccessibilityIncludesCurrentSourceAndSelection() {
        let value = IconDesignerAccessibility.slotValue(
            slot: .center,
            currentSource: "Network",
            isSelected: true
        )

        XCTAssertEqual(value.slotName, .iconDesignerSlotCenter)
        XCTAssertEqual(value.sourceName, "Network")
        XCTAssertTrue(value.isSelected)
    }
}
