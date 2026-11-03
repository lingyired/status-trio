import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class ConnectionCenterSourceTests: XCTestCase {
    private func makeDefaults() throws -> (String, UserDefaults) {
        let suite = "ConnectionCenterSourceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { TestUserDefaults.removeSuite(named: suite) }
        return (suite, defaults)
    }

    func testLegacyAutomaticWithBluetoothMigratesToExclusiveSource() throws {
        let (_, defaults) = try makeDefaults()
        defaults.set("automatic", forKey: SettingsStore.connectionCenterSourceDefaultsKey)
        defaults.set(true, forKey: SettingsStore.replacesNetworkIconWithBluetoothAudioDefaultsKey)
        defaults.set(false, forKey: SettingsStore.prioritizesNetworkErrorsOverBluetoothAudioDefaultsKey)
        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.connectionCenterSource.rawValue, "bluetoothDevice")
        XCTAssertFalse(settings.prioritizesNetworkErrors)
        XCTAssertNil(defaults.object(forKey: SettingsStore.replacesNetworkIconWithBluetoothAudioDefaultsKey))
        XCTAssertNil(defaults.object(forKey: SettingsStore.prioritizesNetworkErrorsOverBluetoothAudioDefaultsKey))
        settings.connectionCenterSource = .power
        XCTAssertEqual(SettingsStore(defaults: defaults).connectionCenterSource, .power)
    }

    func testNumericSourcesGainUnifiedOutagePriorityOnUpgrade() throws {
        for source in ["power", "batteryPercentage"] {
            let (_, defaults) = try makeDefaults()
            defaults.set(source, forKey: SettingsStore.connectionCenterSourceDefaultsKey)
            defaults.set(false, forKey: SettingsStore.prioritizesNetworkErrorsOverInputSourceDefaultsKey)
            let settings = SettingsStore(defaults: defaults)
            XCTAssertEqual(settings.connectionCenterSource.rawValue, source)
            XCTAssertTrue(settings.prioritizesNetworkErrors)
            XCTAssertNil(defaults.object(forKey: SettingsStore.prioritizesNetworkErrorsOverInputSourceDefaultsKey))
        }
    }

    func testFreshInstallStartsOnNetwork() throws {
        let (_, defaults) = try makeDefaults()
        XCTAssertEqual(SettingsStore(defaults: defaults).connectionCenterSource, .network)
    }

    func testLegacyCentreSlotSwitchMigratesToOneChoiceAndIsRemoved() throws {
        let (_, defaults) = try makeDefaults()
        defaults.set(true, forKey: SettingsStore.showsBatteryPercentageInConnectionSlotDefaultsKey)

        let settings = SettingsStore(defaults: defaults)

        XCTAssertEqual(settings.connectionCenterSource, .batteryPercentage)
        XCTAssertNil(defaults.object(forKey: SettingsStore.showsBatteryPercentageInConnectionSlotDefaultsKey),
                     "The migrated key must not override a later manual change")
        XCTAssertEqual(SettingsStore(defaults: defaults).connectionCenterSource, .batteryPercentage,
                       "The migrated choice must survive a second launch")
    }

    func testLegacySwitchWinsOverALegacyStoredSourceJustAsItDidAtDrawTime() throws {
        let (_, defaults) = try makeDefaults()
        defaults.set(true, forKey: SettingsStore.showsBatteryPercentageInConnectionSlotDefaultsKey)
        defaults.set("inputSource", forKey: SettingsStore.connectionCenterSourceDefaultsKey)

        XCTAssertEqual(SettingsStore(defaults: defaults).connectionCenterSource, .batteryPercentage)
        XCTAssertEqual(SettingsStore(defaults: defaults).connectionCenterSource, .batteryPercentage,
                       "The migrated choice must replace the old stored source on disk")
    }

    func testManualPowerChoiceAfterLegacyMigrationSurvivesSecondLaunch() throws {
        let (_, defaults) = try makeDefaults()
        defaults.set(true, forKey: SettingsStore.showsBatteryPercentageInConnectionSlotDefaultsKey)
        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.connectionCenterSource, .batteryPercentage)

        settings.connectionCenterSource = .power

        XCTAssertEqual(SettingsStore(defaults: defaults).connectionCenterSource, .power)
    }

    func testFalseLegacySwitchKeepsStoredInputSource() throws {
        let (_, defaults) = try makeDefaults()
        defaults.set(false, forKey: SettingsStore.showsBatteryPercentageInConnectionSlotDefaultsKey)
        defaults.set("inputSource", forKey: SettingsStore.connectionCenterSourceDefaultsKey)

        XCTAssertEqual(SettingsStore(defaults: defaults).connectionCenterSource, .inputSource)
        XCTAssertEqual(SettingsStore(defaults: defaults).connectionCenterSource, .inputSource)
    }

    func testLegacyInputSourceSelectionSurvivesWithoutTheSwitch() throws {
        let (_, defaults) = try makeDefaults()
        defaults.set("inputSource", forKey: SettingsStore.connectionCenterSourceDefaultsKey)

        XCTAssertEqual(SettingsStore(defaults: defaults).connectionCenterSource, .inputSource)
    }

    func testNewSelectionsPersist() throws {
        let (_, defaults) = try makeDefaults()
        let settings = SettingsStore(defaults: defaults)
        settings.connectionCenterSource = .power

        XCTAssertEqual(SettingsStore(defaults: defaults).connectionCenterSource, .power)
        XCTAssertEqual(SettingsStore(defaults: defaults).connectionIconOptions.centerSource, .power)
    }

    func testPowerInfoBarIsOffByDefaultAndPersists() throws {
        let (_, defaults) = try makeDefaults()
        let settings = SettingsStore(defaults: defaults)
        XCTAssertFalse(settings.showsBatteryPowerInfoBar)
        settings.showsBatteryPowerInfoBar = true
        XCTAssertTrue(SettingsStore(defaults: defaults).showsBatteryPowerInfoBar)
    }

    func testPowerIsTheOnlyChoiceThatKeepsTheSamplerAlive() {
        XCTAssertTrue(ConnectionCenterSource.power.needsPowerSampling)
        for source in ConnectionCenterSource.allCases where source != .power {
            XCTAssertFalse(source.needsPowerSampling, "\(source)")
        }
    }
}
