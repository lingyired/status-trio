import Combine
import XCTest
@testable import StatusTrioCore

/// #275: the Bluetooth icon colour is a persisted setting, defaults to blue,
/// and reaches the shared appearance both surfaces render from. It must not
/// turn the independent volume colour on or off.
@MainActor
final class BluetoothIconColorSettingsTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "StatusTrioCoreTests.BluetoothIconColor.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            fatalError("could not create isolated user defaults suite")
        }
        defaults.removeTestSuite(named: name)
        addTeardownBlock { TestUserDefaults.removeSuite(named: name) }
        return defaults
    }

    func testDefaultsToBlueAndFeedsOptions() {
        let store = SettingsStore(defaults: makeDefaults())
        XCTAssertTrue(store.usesBluetoothAudioIconColor)
        XCTAssertTrue(store.bluetoothAudioIconOptions.usesIconColor)
    }

    func testTurningIconColourOffPersistsWithoutChangingVolumeColour() {
        let defaults = makeDefaults()
        let first = SettingsStore(defaults: defaults)
        first.usesBluetoothAudioVolumeColor = true
        first.usesBluetoothAudioIconColor = false

        let second = SettingsStore(defaults: defaults)
        XCTAssertFalse(second.usesBluetoothAudioIconColor)
        XCTAssertFalse(second.bluetoothAudioIconOptions.usesIconColor)
        XCTAssertTrue(second.usesBluetoothAudioVolumeColor, "volume colour stays independent")
        XCTAssertTrue(second.bluetoothAudioIconOptions.usesVolumeColor)
    }

    func testIconColourChangePublishesASharedAppearance() throws {
        let store = SettingsStore(defaults: makeDefaults())
        var appearances: [StatusIconAppearance] = []
        let cancellable = store.iconAppearancePublisher.sink { appearances.append($0) }
        defer { cancellable.cancel() }

        XCTAssertEqual(try XCTUnwrap(appearances.last).bluetoothAudioOptions.usesIconColor, true)

        store.usesBluetoothAudioIconColor = false

        let updated = try XCTUnwrap(appearances.last)
        XCTAssertFalse(updated.bluetoothAudioOptions.usesIconColor)
        XCTAssertEqual(updated.bluetoothAudioOptions.usesVolumeColor, store.usesBluetoothAudioVolumeColor)
    }
}
