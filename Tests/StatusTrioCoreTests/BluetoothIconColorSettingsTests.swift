import Combine
import XCTest
@testable import StatusTrioCore

/// #275: the Bluetooth icon colour is persisted, defaults to blue, and reaches
/// the shared appearance both surfaces render from without changing the volume
/// colour.
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
        XCTAssertEqual(store.bluetoothIconColor, .systemBlue)
        XCTAssertEqual(store.bluetoothAudioIconOptions.iconColor, .systemBlue)
    }

    func testPrimaryAndCustomPersistWithoutChangingVolumeColour() {
        let defaults = makeDefaults()
        let first = SettingsStore(defaults: defaults)
        first.usesBluetoothAudioVolumeColor = true
        first.bluetoothIconColor = .primary

        let second = SettingsStore(defaults: defaults)
        XCTAssertEqual(second.bluetoothIconColor, .primary)
        XCTAssertEqual(second.bluetoothAudioIconOptions.iconColor, .primary)
        XCTAssertTrue(second.usesBluetoothAudioVolumeColor, "volume colour stays independent")

        let components = BatteryStatusColorComponents(hue: 0.6, saturation: 0.8, brightness: 0.9)
        second.bluetoothIconColor = .custom(components)

        let third = SettingsStore(defaults: defaults)
        XCTAssertEqual(third.bluetoothIconColor, .custom(components))
    }

    func testShortLivedBooleanMigrates() {
        let offDefaults = makeDefaults()
        offDefaults.set(false, forKey: "usesBluetoothAudioIconColor")
        XCTAssertEqual(SettingsStore(defaults: offDefaults).bluetoothIconColor, .primary)

        let onDefaults = makeDefaults()
        onDefaults.set(true, forKey: "usesBluetoothAudioIconColor")
        XCTAssertEqual(SettingsStore(defaults: onDefaults).bluetoothIconColor, .systemBlue)
    }

    func testIconColourChangePublishesASharedAppearance() throws {
        let store = SettingsStore(defaults: makeDefaults())
        var appearances: [StatusIconAppearance] = []
        let cancellable = store.iconAppearancePublisher.sink { appearances.append($0) }
        defer { cancellable.cancel() }

        XCTAssertEqual(try XCTUnwrap(appearances.last).bluetoothAudioOptions.iconColor, .systemBlue)

        store.bluetoothIconColor = .primary

        let updated = try XCTUnwrap(appearances.last)
        XCTAssertEqual(updated.bluetoothAudioOptions.iconColor, .primary)
        XCTAssertEqual(updated.bluetoothAudioOptions.usesVolumeColor, store.usesBluetoothAudioVolumeColor)
    }
}
