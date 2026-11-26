import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class SettingsStoreHardwareRefreshTests: XCTestCase {
    private func withStore(_ prefix: String, _ body: (SettingsStore, UserDefaults) -> Void) {
        let name = "SettingsStoreHardwareRefreshTests.\(prefix).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults, systemChargeLimit: { nil })
        body(store, defaults)
        store.flushPendingPersists()
    }

    func testDefaultsMatchGroupFloorsAndTopAppsDefault() {
        withStore("defaults") { store, _ in
            XCTAssertEqual(store.hardwareCPUUsageRefreshSeconds, 2)
            XCTAssertEqual(store.hardwareGPUUsageRefreshSeconds, 2)
            XCTAssertEqual(store.hardwareMemoryRefreshSeconds, 2)
            XCTAssertEqual(store.hardwareNetworkRefreshSeconds, 1)
            XCTAssertEqual(store.hardwareTemperatureRefreshSeconds, 4)
            XCTAssertEqual(store.hardwareDiskRefreshSeconds, 1)
            XCTAssertEqual(store.hardwareTopAppsRefreshSeconds, 4)
        }
    }

    func testInvalidValuesFallBackToGroupFloor() {
        withStore("invalid") { store, _ in
            store.hardwareCPUUsageRefreshSeconds = 1      // below 2 floor
            XCTAssertEqual(store.hardwareCPUUsageRefreshSeconds, 2)
            store.hardwareTemperatureRefreshSeconds = 2   // below 4 floor
            XCTAssertEqual(store.hardwareTemperatureRefreshSeconds, 4)
            store.hardwareDiskRefreshSeconds = 9          // above 8 cap
            XCTAssertEqual(store.hardwareDiskRefreshSeconds, 1)
            store.hardwareTopAppsRefreshSeconds = 0       // below 1
            XCTAssertEqual(store.hardwareTopAppsRefreshSeconds, 4)
            store.hardwareTopAppsRefreshSeconds = 31      // above 30
            XCTAssertEqual(store.hardwareTopAppsRefreshSeconds, 4)
        }
    }

    func testLegacySingleIntervalSeedsEveryGroup() {
        let name = "SettingsStoreHardwareRefreshTests.migrate6.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(6, forKey: SettingsStore.hardwarePanelRefreshSecondsDefaultsKey)
        let store = SettingsStore(defaults: defaults, systemChargeLimit: { nil })
        XCTAssertEqual(store.hardwareCPUUsageRefreshSeconds, 6)
        XCTAssertEqual(store.hardwareGPUUsageRefreshSeconds, 6)
        XCTAssertEqual(store.hardwareMemoryRefreshSeconds, 6)
        XCTAssertEqual(store.hardwareNetworkRefreshSeconds, 6)
        XCTAssertEqual(store.hardwareTemperatureRefreshSeconds, 6)
        XCTAssertEqual(store.hardwareDiskRefreshSeconds, 6)
    }

    func testLegacyDefaultLeavesGroupsAtTheirFloors() {
        let name = "SettingsStoreHardwareRefreshTests.migrate1.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(1, forKey: SettingsStore.hardwarePanelRefreshSecondsDefaultsKey)
        let store = SettingsStore(defaults: defaults, systemChargeLimit: { nil })
        XCTAssertEqual(store.hardwareCPUUsageRefreshSeconds, 2)
        XCTAssertEqual(store.hardwareNetworkRefreshSeconds, 1)
        XCTAssertEqual(store.hardwareTemperatureRefreshSeconds, 4)
    }

    func testCadenceHelpersReadCurrentValues() {
        withStore("helpers") { store, _ in
            store.hardwareNetworkRefreshSeconds = 5
            XCTAssertEqual(store.hardwareRefreshSeconds(for: .network), 5)
            XCTAssertEqual(store.hardwarePanelCadence(for: .networkDownload), 5)
            XCTAssertNil(store.hardwarePanelCadence(for: .volume))
        }
    }
}
