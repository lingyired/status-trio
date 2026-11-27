import XCTest
@testable import StatusTrioCore

@MainActor
final class MenuBarInstancesStoreTests: XCTestCase {
    private func scratchDefaults() -> UserDefaults {
        let suite = "menubar.store.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testDefaultEmpty() {
        let store = SettingsStore(defaults: scratchDefaults())
        XCTAssertTrue(store.menuBarInstances.instances.isEmpty)
        XCTAssertEqual(store.menuBarInstances.schemaVersion, 2)
    }

    func testPersistAndReload() {
        let defaults = scratchDefaults()
        let store = SettingsStore(defaults: defaults)
        let instance = MenuBarInstance.default()
        store.updateMenuBarInstance(instance)

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.menuBarInstances.instances.count, 1)
        XCTAssertEqual(reloaded.menuBarInstances.instances.first?.id, instance.id)
    }

    func testDeleteRemoves() {
        let store = SettingsStore(defaults: scratchDefaults())
        let a = MenuBarInstance.default()
        let b = MenuBarInstance.default()
        store.updateMenuBarInstance(a)
        store.updateMenuBarInstance(b)
        store.deleteMenuBarInstance(id: a.id)
        XCTAssertEqual(store.menuBarInstances.instances.map(\.id), [b.id])
    }

    func testMoveReordersAndPersists() {
        let defaults = scratchDefaults()
        let store = SettingsStore(defaults: defaults)
        let a = MenuBarInstance(name: "a", top: MenuBarLine(segments: [.metric(.cpuUsage)]))
        let b = MenuBarInstance(name: "b", top: MenuBarLine(segments: [.metric(.gpuUsage)]))
        store.updateMenuBarInstance(a)
        store.updateMenuBarInstance(b)
        XCTAssertEqual(store.menuBarInstances.instances.map(\.name), ["a", "b"])
        store.moveMenuBarInstance(from: 0, to: 1)
        XCTAssertEqual(store.menuBarInstances.instances.map(\.name), ["b", "a"])

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.menuBarInstances.instances.map(\.name), ["b", "a"])
    }

    func testCorruptDataFallsBackToEmpty() {
        let defaults = scratchDefaults()
        defaults.set(Data("not json".utf8), forKey: SettingsStore.menuBarInstancesDefaultsKey)
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.menuBarInstances.instances.isEmpty)
    }
}
