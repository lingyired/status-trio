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

    func testLegacyOptionsMigrationPreservesEveryIconOption() {
        let legacy = IconPresentationConfiguration(
            battery: BatteryIconOptions(
                showsPercentage: false, showsChargingIndicator: true, showsChargingEffect: false,
                showsChargingBoltHeartbeat: false, usesStatusColors: false,
                criticalThreshold: 31, showsPercentageWhenConnected: true,
                textScale: 1.98, ringStrokeScale: 1.5
            ),
            connection: ConnectionIconOptions(
                showsWiFiIconForEthernet: true, showsWiFiIconForHotspot: true,
                showsWiFiIconForTemporaryConnection: true, showsWiFiIconForInternetSharing: true,
                showsBatteryPercentageInConnectionSlot: true, wifiScale: 1.4
            ),
            volume: VolumeIconOptions(displayStyle: .arc, ringStrokeScale: 1.5),
            bluetooth: BluetoothAudioIconOptions(
                replacesNetworkIcon: true, usesVolumeColor: true, prioritizesNetworkErrors: false,
                symbolScale: 1.3, networkIconSymbolOverride: "airpods.pro"
            )
        )
        let migrated = IconConfigurationMigration.makeConfiguration(from: legacy)

        let migratedLegacy = migrated.legacyPresentationConfiguration
        XCTAssertEqual(migratedLegacy.battery, legacy.battery)
        XCTAssertEqual(migratedLegacy.connection.showsWiFiIconForEthernet,
                       legacy.connection.showsWiFiIconForEthernet)
        XCTAssertEqual(migratedLegacy.connection.showsWiFiIconForHotspot,
                       legacy.connection.showsWiFiIconForHotspot)
        XCTAssertEqual(migratedLegacy.connection.showsWiFiIconForTemporaryConnection,
                       legacy.connection.showsWiFiIconForTemporaryConnection)
        XCTAssertEqual(migratedLegacy.connection.showsWiFiIconForInternetSharing,
                       legacy.connection.showsWiFiIconForInternetSharing)
        XCTAssertEqual(migratedLegacy.connection.showsBatteryPercentageInConnectionSlot,
                       legacy.connection.showsBatteryPercentageInConnectionSlot)
        XCTAssertEqual(migratedLegacy.connection.wifiScale, 1.4, accuracy: 0.001)
        XCTAssertEqual(migratedLegacy.volume, legacy.volume)
        XCTAssertEqual(migratedLegacy.bluetooth, legacy.bluetooth)
        XCTAssertEqual(migrated.appearance.outerRing.strokeScale, 1.5)
        XCTAssertEqual(migrated.appearance.footer.strokeScale, 1.5)
    }

    func testStoreMigratesLegacyDefaultsAndKeepsOldKeys() throws {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: SettingsStore.showsBatteryPercentageDefaultsKey)
        defaults.set(true, forKey: SettingsStore.showsBatteryPercentageInConnectionSlotDefaultsKey)
        defaults.set(true, forKey: SettingsStore.replacesNetworkIconWithBluetoothAudioDefaultsKey)
        defaults.set("airpods.pro", forKey: SettingsStore.bluetoothNetworkIconSymbolNameDefaultsKey)
        defaults.set(VolumeDisplayStyle.arc.rawValue, forKey: SettingsStore.volumeDisplayStyleDefaultsKey)
        defaults.set(RingStrokeStyle.bold.rawValue, forKey: SettingsStore.ringStrokeStyleDefaultsKey)

        let store = SettingsStore(defaults: defaults)
        let data = try XCTUnwrap(defaults.data(forKey: SettingsStore.iconConfigurationDefaultsKey))
        let migrated = try IconConfigurationCodec.decode(data)

        XCTAssertFalse(store.showsBatteryPercentage)
        XCTAssertTrue(store.showsBatteryPercentageInConnectionSlot)
        XCTAssertTrue(store.replacesNetworkIconWithBluetoothAudio)
        XCTAssertEqual(store.bluetoothNetworkIconSymbolName, "airpods.pro")
        XCTAssertEqual(store.volumeDisplayStyle, .arc)
        XCTAssertEqual(migrated.legacyPresentationConfiguration, store.iconPresentationConfiguration)
        XCTAssertEqual(defaults.object(forKey: SettingsStore.showsBatteryPercentageDefaultsKey) as? Bool, false)
        XCTAssertEqual(defaults.string(forKey: SettingsStore.volumeDisplayStyleDefaultsKey), VolumeDisplayStyle.arc.rawValue)
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
        let cancellable = store.$iconConfiguration.sink { snapshots.append($0) }
        defer { cancellable.cancel() }
        let count = snapshots.count

        store.updateIconConfiguration { $0.appearance.outerRing.strokeScale = 1.5 }
        XCTAssertEqual(snapshots.count, count + 1)
        XCTAssertEqual(snapshots.last?.appearance.outerRing.strokeScale, 1.5)

        store.updateIconConfiguration { $0.appearance.outerRing.strokeScale = 1.5 }
        XCTAssertEqual(snapshots.count, count + 1)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let name = "IconConfigurationMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }
}
