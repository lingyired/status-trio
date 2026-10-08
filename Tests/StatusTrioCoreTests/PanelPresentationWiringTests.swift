import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class PanelPresentationWiringTests: XCTestCase {
    /// The Bluetooth row and summary wiring is pinned by `BluetoothSummaryTests`,
    /// `BluetoothDeviceActionsTests`, and `BluetoothSummaryLayoutTests`, which
    /// exercise the controller-driven Bluetooth surface this branch keeps. The
    /// presentation-state variant of that surface is not part of the merge, so
    /// there is nothing left to wire here beyond the battery details panel below.

    func testBatteryDetailsAppearanceAndBackCallbackPairTheCollectorLifecycle() async {
        var activations = 0
        var closes = 0
        let actions = StatusPanelActions(
            activateBatteryDetails: { _ in activations += 1 },
            closeBatteryDetails: { closes += 1 }
        )
        let localization = Localization(preferredLanguages: ["en"])
        let state = PanelDetailMapper.battery(
            status: BatteryStatus(
                rawPercentage: 80,
                isPresent: true,
                isCharging: false,
                isLowPowerMode: false,
                isConnectedToPower: false
            ),
            details: nil,
            localization: localization
        )
        let appeared = expectation(description: "battery details start their collector when displayed")
        let view = BatteryDetailsView(
            state: state,
            onBack: { actions.batteryDetailsClosed() },
            onOpenBatterySettings: {},
            onCopyValue: { _ in },
            onAppear: {
                actions.batteryDetailsAppeared()
                appeared.fulfill()
            }
        )
        let hostingView = NSHostingView(rootView: view.environmentObject(localization))
        hostingView.frame = NSRect(x: 0, y: 0, width: 330, height: 300)
        hostingView.layoutSubtreeIfNeeded()
        await fulfillment(of: [appeared], timeout: 1)
        XCTAssertEqual(activations, 1)

        view.onBack()
        XCTAssertEqual(closes, 1, "the back route closes the collector started by view appearance")
    }
}
