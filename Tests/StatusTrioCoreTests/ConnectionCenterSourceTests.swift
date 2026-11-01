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

    func testFreshInstallStartsOnAutomatic() throws {
        let (_, defaults) = try makeDefaults()
        XCTAssertEqual(SettingsStore(defaults: defaults).connectionCenterSource, .automatic)
    }

    func testLegacyCentreSlotSwitchMigratesToOneChoiceAndIsRemoved() throws {
        let (_, defaults) = try makeDefaults()
        defaults.set(true, forKey: SettingsStore.showsBatteryPercentageInConnectionSlotDefaultsKey)

        let settings = SettingsStore(defaults: defaults)

        XCTAssertEqual(settings.connectionCenterSource, .batteryPercentage)
        XCTAssertNil(defaults.object(forKey: SettingsStore.showsBatteryPercentageInConnectionSlotDefaultsKey),
                     "The migrated key must not override a later manual change")
    }

    func testLegacySwitchWinsOverALegacyStoredSourceJustAsItDidAtDrawTime() throws {
        let (_, defaults) = try makeDefaults()
        defaults.set(true, forKey: SettingsStore.showsBatteryPercentageInConnectionSlotDefaultsKey)
        defaults.set("inputSource", forKey: SettingsStore.connectionCenterSourceDefaultsKey)

        XCTAssertEqual(SettingsStore(defaults: defaults).connectionCenterSource, .batteryPercentage)
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
