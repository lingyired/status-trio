import XCTest
@testable import StatusTrioCore

@MainActor
final class MenuBarInstancesTransferTests: XCTestCase {
    private func scratchDefaults() -> UserDefaults {
        let suite = "menubar.transfer.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func jsonString(_ config: MenuBarInstancesConfiguration) -> String {
        let data = try! JSONEncoder().encode(config)
        return String(decoding: data, as: UTF8.self)
    }

    func testSnapshotContainsMenuBarInstances() {
        let store = SettingsStore(defaults: scratchDefaults())
        let snapshot = SettingsPreferenceCatalog.snapshot(store)
        XCTAssertNotNil(snapshot["menuBarInstances"])
    }

    func testRoundTripOneInstance() {
        let source = SettingsStore(defaults: scratchDefaults())
        let instance = MenuBarInstance.default()
        source.updateMenuBarInstance(instance)

        let snapshot = SettingsPreferenceCatalog.snapshot(source)
        let target = SettingsStore(defaults: scratchDefaults())
        SettingsPreferenceCatalog.apply(snapshot, to: target)

        XCTAssertEqual(target.menuBarInstances.instances.count, 1)
        XCTAssertEqual(target.menuBarInstances.instances.first?.id, instance.id)
    }

    func testImportOver20Rejected() {
        let instances = (0..<21).map { _ in MenuBarInstance.default() }
        let payload = jsonString(MenuBarInstancesConfiguration(instances: instances))
        let prepared = SettingsPreferenceCatalog.prepare(["menuBarInstances": .string(payload)])
        XCTAssertFalse(prepared.warnings.isEmpty)
    }

    func testCorruptImportFallsBack() {
        let prepared = SettingsPreferenceCatalog.prepare(["menuBarInstances": .string("not json")])
        XCTAssertFalse(prepared.warnings.isEmpty)
    }
}
