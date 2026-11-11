import XCTest
@testable import StatusTrioCore

@MainActor
final class HardwareMonitorSettingsTests: XCTestCase {
    private func makeSuite() -> (UserDefaults, String) {
        let name = "StatusTrioCoreTests.HardwareMonitorSettings.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    func testDefaultsShowAllMetricsInCanonicalOrder() {
        let (defaults, name) = makeSuite()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.hardwareMonitorMetricOrder, HardwareMonitorMetric.allCases)
        XCTAssertEqual(store.enabledHardwareMonitorMetrics, Set(HardwareMonitorMetric.allCases))
        XCTAssertEqual(store.visibleHardwareMetrics, HardwareMonitorMetric.allCases)
    }

    func testDisablingAndReorderingPersistAndFilterVisibleMetrics() {
        let (defaults, name) = makeSuite()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        store.setHardwareMonitorMetric(.gpuUsage, enabled: false)
        store.moveHardwareMonitorMetrics(fromOffsets: IndexSet(integer: 5), toOffset: 0) // fan to front
        XCTAssertEqual(store.hardwareMonitorMetricOrder.first, .fan)
        XCTAssertFalse(store.enabledHardwareMonitorMetrics.contains(.gpuUsage))
        XCTAssertFalse(store.visibleHardwareMetrics.contains(.gpuUsage))

        let reopened = SettingsStore(defaults: defaults)
        XCTAssertEqual(reopened.hardwareMonitorMetricOrder.first, .fan)
        XCTAssertEqual(reopened.enabledHardwareMonitorMetrics,
                       Set(HardwareMonitorMetric.allCases).subtracting([.gpuUsage]))
        XCTAssertEqual(reopened.visibleHardwareMetrics,
                       reopened.hardwareMonitorMetricOrder.filter { $0 != .gpuUsage })
    }

    func testLastEnabledMetricCannotBeDisabled() {
        let (defaults, name) = makeSuite()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        for metric in HardwareMonitorMetric.allCases.dropLast() {
            store.setHardwareMonitorMetric(metric, enabled: false)
        }
        XCTAssertEqual(store.enabledHardwareMonitorMetrics.count, 1)
        guard let remaining = store.enabledHardwareMonitorMetrics.first else {
            return XCTFail("expected one enabled metric")
        }
        store.setHardwareMonitorMetric(remaining, enabled: false)
        XCTAssertEqual(store.enabledHardwareMonitorMetrics, [remaining],
                       "the last enabled tile must stay on")
    }

    func testStoredUnknownAndDuplicateValuesAreSanitized() {
        let (defaults, name) = makeSuite()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["fan", "bogus", "fan", "cpuUsage"],
                     forKey: SettingsStore.hardwareMonitorMetricOrderDefaultsKey)
        defaults.set(["fan", "bogus"],
                     forKey: SettingsStore.enabledHardwareMonitorMetricsDefaultsKey)
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(Array(store.hardwareMonitorMetricOrder.prefix(2)), [.fan, .cpuUsage])
        XCTAssertEqual(Set(store.hardwareMonitorMetricOrder), Set(HardwareMonitorMetric.allCases),
                       "missing known metrics are appended without duplication")
        XCTAssertEqual(store.enabledHardwareMonitorMetrics, [.fan])
    }

    func testEmptyStoredEnabledSetFallsBackToDefaults() {
        let (defaults, name) = makeSuite()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set([String](), forKey: SettingsStore.enabledHardwareMonitorMetricsDefaultsKey)
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.enabledHardwareMonitorMetrics,
                       SettingsStore.defaultEnabledHardwareMonitorMetrics,
                       "an empty/corrupt set must not leave the card with no metric")
    }

    func testShowInPanelToggleUsesPopupSection() {
        let (defaults, name) = makeSuite()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.enabledPopupSections.contains(.hardwareMonitor))
        store.setPopupSection(.hardwareMonitor, enabled: true)
        XCTAssertTrue(store.enabledPopupSections.contains(.hardwareMonitor))
    }
}
