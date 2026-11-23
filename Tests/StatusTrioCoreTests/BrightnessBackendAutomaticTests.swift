import XCTest
@testable import StatusTrioCore

@MainActor
final class BrightnessBackendAutomaticTests: XCTestCase {
    private func makeSuite() -> (name: String, defaults: UserDefaults) {
        let name = "StatusTrioBrightnessAutomaticTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (name, defaults)
    }

    func testUnconfiguredExternalDisplayDefaultsToAutomatic() {
        let suite = makeSuite()
        defer { suite.defaults.removePersistentDomain(forName: suite.name) }

        let store = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(
            store.externalBrightnessConfiguration(for: "new-display").backend,
            .automatic
        )
    }

    func testExplicitDDCSelectionIsPreservedAcrossReload() {
        let suite = makeSuite()
        defer { suite.defaults.removePersistentDomain(forName: suite.name) }

        let first = SettingsStore(defaults: suite.defaults)
        first.setExternalBrightnessConfiguration(
            ExternalBrightnessConfiguration(backend: .directDDC, betterDisplayUUID: nil),
            for: "new-display"
        )

        let second = SettingsStore(defaults: suite.defaults)
        XCTAssertEqual(
            second.externalBrightnessConfiguration(for: "new-display").backend,
            .directDDC,
            "an explicit backend choice must not be replaced by automatic"
        )
    }
}
