import XCTest
@testable import StatusTrioCore

@MainActor
final class MenuBarInstancesListModelTests: XCTestCase {
    private func scratchStore() -> SettingsStore {
        let suite = "menubar.list.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(defaults: defaults)
    }

    func testAddPresetCPU() {
        let store = scratchStore()
        let model = MenuBarInstancesListModel(store: store)
        model.addPreset(.cpu)
        XCTAssertEqual(store.menuBarInstances.instances.count, 1)
        XCTAssertEqual(store.menuBarInstances.instances[0].top?.segments, [.text("CPU "), .metric(.cpuUsage)])
        XCTAssertNil(store.menuBarInstances.instances[0].bottom)
    }

    func testCanAddFalseAt20() {
        let store = scratchStore()
        let model = MenuBarInstancesListModel(store: store)
        for _ in 0..<20 { model.addPreset(.cpu) }
        XCTAssertFalse(model.canAdd)
        model.addPreset(.cpu)
        XCTAssertEqual(store.menuBarInstances.instances.count, 20)
    }

    func testDuplicateNewID() {
        let store = scratchStore()
        let model = MenuBarInstancesListModel(store: store)
        model.addPreset(.memory)
        let original = store.menuBarInstances.instances[0]
        model.duplicate(id: original.id)
        XCTAssertEqual(store.menuBarInstances.instances.count, 2)
        XCTAssertNotEqual(store.menuBarInstances.instances[1].id, original.id)
        XCTAssertEqual(store.menuBarInstances.instances[1].top?.segments, original.top?.segments)
    }

    func testDeleteAndMovePersist() {
        let store = scratchStore()
        let model = MenuBarInstancesListModel(store: store)
        model.addPreset(.cpu)
        let a = store.menuBarInstances.instances[0]
        model.addPreset(.memory)
        let firstID = store.menuBarInstances.instances[0].id
        model.move(from: 0, to: 1)
        XCTAssertEqual(store.menuBarInstances.instances[1].id, firstID)
        model.delete(id: a.id)
        XCTAssertEqual(store.menuBarInstances.instances.count, 1)
    }
}
