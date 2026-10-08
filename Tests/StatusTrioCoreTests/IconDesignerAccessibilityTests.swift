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
