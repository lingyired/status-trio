import XCTest
@testable import StatusTrioCore

final class IconDesignerEditHistoryTests: XCTestCase {
    func testIgnoresNoopCapsAt64AndUndoesOnlyMatchingCurrentSnapshot() {
        var history = IconDesignerEditHistory()
        let initial = snapshot()
        history.record(before: initial, after: initial)
        XCTAssertEqual(history.count, 0)

        var before = initial
        var beforeLast: IconDesignerEditSnapshot?
        for value in 1...65 {
            if value == 65 { beforeLast = before }
            var after = before
            after.configuration.behaviors.networkCenter.showsWiFiIconForEthernet = value.isMultiple(of: 2)
            after.connectedBluetoothAddress = "AA:BB:CC:DD:EE:\(String(format: "%02X", value))"
            history.record(before: before, after: after)
            before = after
        }
        XCTAssertEqual(history.count, 64)
        XCTAssertEqual(history.undo(current: before), beforeLast)
        XCTAssertEqual(history.count, 63)
    }

    func testUndoRestoresConfigurationAndBluetoothAddressesAndRejectsStaleSnapshot() {
        var history = IconDesignerEditHistory()
        let before = snapshot()
        var after = before
        after.configuration.behaviors.networkCenter.showsWiFiIconForEthernet = true
        after.connectedBluetoothAddress = "01:02:03:04:05:06"
        after.airPodsAddress = "10:20:30:40:50:60"
        history.record(before: before, after: after)

        var staleHistory = IconDesignerEditHistory()
        staleHistory.record(before: before, after: after)
        XCTAssertNil(staleHistory.undo(current: before), "An external mutation must not replay stale undo state.")
        XCTAssertEqual(history.undo(current: after), before)
        XCTAssertEqual(history.count, 0)
    }

    func testInvalidatingExternalChangesClearsUndoAndSnapshotOmitsSamples() {
        var history = IconDesignerEditHistory()
        let before = snapshot()
        var after = before
        after.refreshesAirPodsBatteryForIcon.toggle()
        history.record(before: before, after: after)
        history.invalidateForExternalChange()
        XCTAssertNil(history.undo(current: after))
        XCTAssertFalse(Mirror(reflecting: before).children.contains { $0.label == "samples" })
    }

    private func snapshot() -> IconDesignerEditSnapshot {
        IconDesignerEditSnapshot(configuration: .classic, airPodsAddress: nil,
                                 connectedBluetoothAddress: nil, bluetoothNetworkAddress: nil,
                                 refreshesAirPodsBatteryForIcon: false)
    }
}
