import XCTest
@testable import StatusTrioCore

final class MenuBarInstanceRightClickMenuTests: XCTestCase {
    func testQuickActionPlusDisable() {
        let entries = MenuBarInstanceRightClickMenu.entries(
            rightClick: .quickAction("toggleWiFi"),
            resolvedTitleKey: .hardwareMonitorCPU,
            resolvedEnabled: true
        )
        XCTAssertEqual(entries.count, 3)
        guard case .action(let id, _, let enabled) = entries[0] else { return XCTFail("expected action") }
        XCTAssertEqual(id, "toggleWiFi")
        XCTAssertTrue(enabled)
        XCTAssertEqual(entries[1], .separator)
        guard case .action(let disableID, _, _) = entries[2] else { return XCTFail("expected action") }
        XCTAssertEqual(disableID, MenuBarInstanceRightClickMenu.disableID)
    }

    func testSameAsMainIcon() {
        let entries = MenuBarInstanceRightClickMenu.entries(
            rightClick: .sameAsMainIcon,
            resolvedTitleKey: .hardwareMonitorGPU,
            resolvedEnabled: false
        )
        guard case .action(let id, _, let enabled) = entries[0] else { return XCTFail("expected action") }
        XCTAssertEqual(id, "mainIcon")
        XCTAssertFalse(enabled)
    }

    func testNeverContainsDelete() {
        let entries = MenuBarInstanceRightClickMenu.entries(
            rightClick: .quickAction("refreshStatus"),
            resolvedTitleKey: .hardwareMonitorCPU,
            resolvedEnabled: true
        )
        for entry in entries {
            if case .action(let id, _, _) = entry {
                XCTAssertFalse(id.lowercased().contains("delete"))
            }
        }
    }
}
