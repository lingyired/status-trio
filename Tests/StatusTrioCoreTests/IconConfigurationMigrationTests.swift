import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class IconConfigurationMigrationTests: XCTestCase {
    func testOlderV1PayloadWithoutAirPodsBehaviorDecodesAsSingleRingAndRoundTripsDual() throws {
        let encoded = try JSONEncoder().encode(IconConfigurationV1.classic)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var behaviors = try XCTUnwrap(object["behaviors"] as? [String: Any])
        behaviors.removeValue(forKey: "airPodsRing")
        object["behaviors"] = behaviors
        let olderPayload = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(IconConfigurationV1.self, from: olderPayload)
        XCTAssertEqual(decoded.behaviors.airPodsRing, .single)

        var dual = decoded
        dual.behaviors.airPodsRing = .dual
        XCTAssertEqual(try JSONDecoder().decode(IconConfigurationV1.self, from: JSONEncoder().encode(dual)), dual)
    }

    func testOlderV1PayloadWithoutAirPodsTopSymbolDecodesDisabledAndPersistsEdits() throws {
        let encoded = try JSONEncoder().encode(IconConfigurationV1.classic)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var behaviors = try XCTUnwrap(object["behaviors"] as? [String: Any])
        behaviors.removeValue(forKey: "showsAirPodsTopSymbol")
        object["behaviors"] = behaviors
        let olderPayload = try JSONSerialization.data(withJSONObject: object)

        var decoded = try JSONDecoder().decode(IconConfigurationV1.self, from: olderPayload)
        XCTAssertFalse(decoded.behaviors.showsAirPodsTopSymbol)
        decoded.behaviors.showsAirPodsTopSymbol = true
        XCTAssertTrue(try JSONDecoder().decode(IconConfigurationV1.self, from: JSONEncoder().encode(decoded))
            .behaviors.showsAirPodsTopSymbol)
    }

    func testLegacyConfigurationMigrationDefaultsToDualWithoutChangingLegacySceneSelection() {
        let migrated = IconConfigurationMigration.makeConfiguration(from: .standard)

        XCTAssertEqual(migrated.behaviors.airPodsRing, .dual)
        XCTAssertEqual(migrated.composition.outerRing.primary, .automaticLegacy)
        XCTAssertEqual(migrated.composition.center.primary, .automaticLegacy)
    }

    func testStoreKeepsStoredSingleAirPodsBehavior() throws {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let encoded = try JSONEncoder().encode(IconConfigurationV1.classic)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var behaviors = try XCTUnwrap(object["behaviors"] as? [String: Any])
        behaviors["airPodsRing"] = AirPodsRingBehavior.single.rawValue
        object["behaviors"] = behaviors
        defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: SettingsStore.iconConfigurationDefaultsKey)

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.iconConfiguration.behaviors.airPodsRing, .single)
        let persisted = try XCTUnwrap(defaults.data(forKey: SettingsStore.iconConfigurationDefaultsKey))
        XCTAssertEqual(try IconConfigurationCodec.decode(persisted).behaviors.airPodsRing, .single)
    }

    func testStandardMigrationKeepsScene() {
        let inputs = IconPresentationInputs(snapshot: PresentationFixtures.snapshot(), audioIcon: nil)
        let migrated = IconConfigurationMigration.makeConfiguration(from: .standard)

        XCTAssertEqual(
            IconPresentationMapper.scene(inputs: inputs, configuration: .standard),
            IconPresentationMapper.scene(inputs: inputs, configuration: migrated.legacyPresentationConfiguration)
        )
    }

    func testStorePersistsV1WiFiScaleMigrationOnLoad() throws {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        var oldConfiguration = IconConfigurationV1.classic
        oldConfiguration.behaviors.networkCenter.wifiScale = 2.1
        oldConfiguration.appearance.center.symbolScale = 1.2
        let encoded = try JSONEncoder().encode(oldConfiguration)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "wifiScaleMigrationVersion")
        defaults.set(try JSONSerialization.data(withJSONObject: object),
                     forKey: SettingsStore.iconConfigurationDefaultsKey)

        let store = SettingsStore(defaults: defaults)
        let saved = try XCTUnwrap(defaults.data(forKey: SettingsStore.iconConfigurationDefaultsKey))
        let reloaded = try IconConfigurationCodec.decode(saved)

        XCTAssertEqual(store.iconConfiguration.appearance.center.symbolScale, 2.52, accuracy: 0.001)
        XCTAssertEqual(reloaded.appearance.center.symbolScale, 2.52, accuracy: 0.001)
        XCTAssertEqual(reloaded.behaviors.networkCenter.wifiScale, 1, accuracy: 0.001)
        XCTAssertNotEqual(saved, try JSONSerialization.data(withJSONObject: object))
    }

    func testSecondLaunchDoesNotRemigrateOrOverwriteCurrentConfiguration() throws {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let first = SettingsStore(defaults: defaults)
        first.showsBatteryPercentage = false
        let saved = try XCTUnwrap(defaults.data(forKey: SettingsStore.iconConfigurationDefaultsKey))
        defaults.set(true, forKey: SettingsStore.showsBatteryPercentageDefaultsKey)

        let second = SettingsStore(defaults: defaults)

        XCTAssertFalse(second.showsBatteryPercentage)
        XCTAssertEqual(defaults.data(forKey: SettingsStore.iconConfigurationDefaultsKey), saved)
    }

    func testCorruptConfigurationIsPreservedUntilExplicitReset() throws {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let invalid = Data([0xDE, 0xAD, 0xBE, 0xEF])
        defaults.set(invalid, forKey: SettingsStore.iconConfigurationDefaultsKey)

        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(defaults.data(forKey: SettingsStore.iconConfigurationDefaultsKey), invalid)
        XCTAssertNotNil(store.iconConfigurationLoadError)

        store.resetIconConfiguration()

        XCTAssertNil(store.iconConfigurationLoadError)
        XCTAssertEqual(
            try IconConfigurationCodec.decode(XCTUnwrap(defaults.data(forKey: SettingsStore.iconConfigurationDefaultsKey))),
            .classic
        )
    }

    func testConfigurationUpdatePublishesOneCompleteSnapshotAndNoOpPublishesNothing() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        var snapshots: [IconConfigurationV1] = []
        let cancellable = store.iconConfigurationPublisher.sink { snapshots.append($0) }
        defer { cancellable.cancel() }
        let count = snapshots.count

        store.updateIconConfiguration { $0.appearance.outerRing.strokeScale = 1.5 }
        XCTAssertEqual(snapshots.count, count + 1)
        XCTAssertEqual(snapshots.last?.appearance.outerRing.strokeScale, 1.5)

        store.updateIconConfiguration { $0.appearance.outerRing.strokeScale = 1.5 }
        XCTAssertEqual(snapshots.count, count + 1)
    }

    // MARK: - Explicit input-source centre + global network policy

    func testInputSourceCenterSourceRoundTrips() throws {
        var value = IconConfigurationV1.classic
        value.composition.center = SlotSelection(primary: .inputSource, fallback: .systemBatteryPercentage)

        let decoded = try IconConfigurationCodec.decode(IconConfigurationCodec.encode(value))

        XCTAssertEqual(decoded.composition.center.primary, .inputSource)
        XCTAssertEqual(decoded.composition.center.fallback, .systemBatteryPercentage)
    }

    func testOlderV1PayloadWithoutCenterMigrationVersionPreservesExplicitCenter() throws {
        var value = IconConfigurationV1.classic
        value.composition.center = SlotSelection(primary: .bluetoothAudioOutput)
        let encoded = try JSONEncoder().encode(value)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "centerSourceMigrationVersion")

        let decoded = try IconConfigurationCodec.decode(try JSONSerialization.data(withJSONObject: object))

        XCTAssertNil(decoded.centerSourceMigrationVersion)
        XCTAssertEqual(decoded.composition.center.primary, .bluetoothAudioOutput)
    }

    func testCenterCompatibilityFoldsOnlyNetworkAndAutomaticLegacy() {
        let inputSourceLegacy = IconConfigurationMigration.LegacyCenterPreferences(
            connectionCenterSource: .inputSource,
            prioritizesNetworkErrorsOverInputSource: nil,
            prioritizesNetworkErrorsOverBluetoothAudio: nil
        )
        let cases: [(CenterSource, CenterSource)] = [
            (.network, .inputSource),
            (.automaticLegacy, .inputSource),
            (.bluetoothAudioOutput, .bluetoothAudioOutput),
            (.systemBatteryPercentage, .systemBatteryPercentage),
            (.none, .none),
        ]

        for (stored, expected) in cases {
            var value = IconConfigurationV1.classic
            value.centerSourceMigrationVersion = nil
            value.composition.center = SlotSelection(primary: stored)

            let migrated = IconConfigurationMigration.applyingCenterCompatibility(
                inputSourceLegacy, to: value, hadStoredV1: true
            )

            XCTAssertEqual(migrated.composition.center.primary, expected, "stored \(stored)")
            XCTAssertEqual(migrated.centerSourceMigrationVersion, 1)
        }
    }

    func testCenterCompatibilityLeavesAlreadyMigratedConfigurationUntouched() {
        var value = IconConfigurationV1.classic
        value.composition.center = SlotSelection(primary: .network)
        value.composition.centerOverride.networkProblemOverridesPrimary = false
        // Migration marker already present: a later explicit user choice must survive.
        value.centerSourceMigrationVersion = 1
        let legacy = IconConfigurationMigration.LegacyCenterPreferences(
            connectionCenterSource: .inputSource,
            prioritizesNetworkErrorsOverInputSource: true,
            prioritizesNetworkErrorsOverBluetoothAudio: true
        )

        let migrated = IconConfigurationMigration.applyingCenterCompatibility(legacy, to: value, hadStoredV1: true)

        XCTAssertEqual(migrated.composition.center.primary, .network)
        XCTAssertFalse(migrated.composition.centerOverride.networkProblemOverridesPrimary)
    }

    func testStoredV1CenterOverrideFalseIsNeverReenabledByLegacyDefaults() {
        var value = IconConfigurationV1.classic
        value.composition.centerOverride.networkProblemOverridesPrimary = false
        value.centerSourceMigrationVersion = nil
        let legacyDefaults = IconConfigurationMigration.LegacyCenterPreferences(
            connectionCenterSource: nil,
            prioritizesNetworkErrorsOverInputSource: true,
            prioritizesNetworkErrorsOverBluetoothAudio: true
        )

        let migrated = IconConfigurationMigration.applyingCenterCompatibility(
            legacyDefaults, to: value, hadStoredV1: true
        )

        XCTAssertFalse(migrated.composition.centerOverride.networkProblemOverridesPrimary)
    }

    func testFreshMigrationSeedsGlobalPolicyOnlyFromExplicitLegacyFlags() {
        var value = IconConfigurationV1.classic
        value.centerSourceMigrationVersion = nil
        let explicitOn = IconConfigurationMigration.LegacyCenterPreferences(
            connectionCenterSource: nil,
            prioritizesNetworkErrorsOverInputSource: true,
            prioritizesNetworkErrorsOverBluetoothAudio: nil
        )
        let inventedDefaults = IconConfigurationMigration.LegacyCenterPreferences(
            connectionCenterSource: nil,
            prioritizesNetworkErrorsOverInputSource: nil,
            prioritizesNetworkErrorsOverBluetoothAudio: nil
        )

        XCTAssertTrue(IconConfigurationMigration.applyingCenterCompatibility(
            explicitOn, to: value, hadStoredV1: false
        ).composition.centerOverride.networkProblemOverridesPrimary)
        XCTAssertFalse(IconConfigurationMigration.applyingCenterCompatibility(
            inventedDefaults, to: value, hadStoredV1: false
        ).composition.centerOverride.networkProblemOverridesPrimary)
    }

    func testLegacyPreferencesReadDoesNotInventUnpersistedDefaults() throws {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let preferences = IconConfigurationMigration.LegacyCenterPreferences.read(from: defaults)

        XCTAssertNil(preferences.connectionCenterSource)
        XCTAssertNil(preferences.prioritizesNetworkErrorsOverInputSource)
        XCTAssertNil(preferences.prioritizesNetworkErrorsOverBluetoothAudio)
    }

    func testStoreMigratesStoredV1NetworkToInputSourceOnceFromExplicitLegacy() throws {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        var value = IconConfigurationV1.classic
        value.composition.center = SlotSelection(primary: .network)
        value.centerSourceMigrationVersion = nil
        defaults.set(try JSONEncoder().encode(value), forKey: SettingsStore.iconConfigurationDefaultsKey)
        defaults.set(ConnectionCenterSource.inputSource.rawValue, forKey: SettingsStore.connectionCenterSourceDefaultsKey)

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.iconConfiguration.composition.center.primary, .inputSource)
        XCTAssertEqual(store.iconConfiguration.centerSourceMigrationVersion, 1)

        let second = SettingsStore(defaults: defaults)
        XCTAssertEqual(second.iconConfiguration.composition.center.primary, .inputSource)
    }

    func testFreshInstallDoesNotEnableGlobalPolicyOrInputSourceWithoutStoredKeys() throws {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let store = SettingsStore(defaults: defaults)

        XCTAssertNotEqual(store.iconConfiguration.composition.center.primary, .inputSource)
        XCTAssertFalse(store.iconConfiguration.composition.centerOverride.networkProblemOverridesPrimary)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let name = "IconConfigurationMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }
}
