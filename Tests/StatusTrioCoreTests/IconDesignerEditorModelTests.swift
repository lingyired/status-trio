import XCTest
@testable import StatusTrioCore

@MainActor
final class IconDesignerEditorModelTests: XCTestCase {
    func testSettingsEditorTransactionUndoRestoresConfigurationAndSelectedDeviceAddress() {
        let name = "IconDesignerEditorModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        let model = IconDesignerEditorModel(store: store)
        let before = store.iconConfiguration

        model.perform {
            store.updateIconConfiguration { $0.appearance.center.symbolScale = 2.25 }
            store.connectedBluetoothIconDeviceAddress = "01:02:03:04:05:06"
        }

        XCTAssertTrue(model.canUndo)
        XCTAssertEqual(store.connectedBluetoothIconDeviceAddress, "01:02:03:04:05:06")
        model.undo()
        XCTAssertEqual(store.iconConfiguration, before)
        XCTAssertNil(store.connectedBluetoothIconDeviceAddress)
        XCTAssertFalse(model.canUndo)
    }

    func testColorGestureCoalescesAndExternalSettingsChangeInvalidatesHistory() {
        let name = "IconDesignerEditorModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        let model = IconDesignerEditorModel(store: store)
        let group = "appearance.color.center.primary"
        model.beginCoalescingGroup(group)
        model.updateIconConfiguration(coalescingKey: group) { $0.appearance.center.symbolScale = 1.5 }
        model.updateIconConfiguration(coalescingKey: group) { $0.appearance.center.symbolScale = 2 }
        model.endCoalescingGroup(group)
        XCTAssertEqual(model.historyCountForTesting, 1)
        XCTAssertTrue(model.canUndo)

        store.updateIconConfiguration { $0.composition.center.primary = .none }
        XCTAssertFalse(model.canUndo)
        XCTAssertTrue(model.hasExternalChangeNotice)
    }

    func testSlowGestureUsesExplicitBoundaryAndSeparateGesturesRemainSeparate() {
        let name = "IconDesignerEditorModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        let model = IconDesignerEditorModel(store: store)
        let key = "appearance.scale.center"
        model.beginCoalescingGroup(key)
        model.updateIconConfiguration(coalescingKey: key) { $0.appearance.center.effectiveSymbolScale = 1.5 }
        model.updateIconConfiguration(coalescingKey: key) { $0.appearance.center.effectiveSymbolScale = 2.5 }
        model.endCoalescingGroup(key)
        XCTAssertEqual(model.historyCountForTesting, 1)

        model.beginCoalescingGroup(key)
        model.updateIconConfiguration(coalescingKey: key) { $0.appearance.center.effectiveSymbolScale = 3 }
        model.endCoalescingGroup(key)
        XCTAssertEqual(model.historyCountForTesting, 2)
    }

    func testScaleGestureClampsEditedValueAndUndoRestoresOutOfRangeHistoricalValue() {
        let name = "IconDesignerEditorModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        store.updateIconConfiguration { $0.appearance.center.effectiveSymbolScale = 4.25 }
        let model = IconDesignerEditorModel(store: store)
        let key = "appearance.scale.center"

        model.beginCoalescingGroup(key)
        model.updateIconConfiguration(coalescingKey: key) {
            IconDesignerEditingModel.settingCommonPercentageScale(1.2, in: &$0)
        }
        model.updateIconConfiguration(coalescingKey: key) {
            IconDesignerEditingModel.settingCommonPercentageScale(1.8, in: &$0)
        }
        model.endCoalescingGroup(key)

        XCTAssertEqual(model.historyCountForTesting, 1)
        XCTAssertEqual(try! XCTUnwrap(store.iconConfiguration.appearance.center.normalizedSizePercentage), 1.8, accuracy: 0.001)
        model.undo()
        XCTAssertEqual(try! XCTUnwrap(store.iconConfiguration.appearance.center.effectiveSymbolScale), 4.25, accuracy: 0.001)
    }

    func testUnrelatedPlacementChangeKeepsIconUndoHistory() {
        let name = "IconDesignerEditorModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        let model = IconDesignerEditorModel(store: store)
        model.updateIconConfiguration { $0.appearance.center.effectiveSymbolScale = 2 }
        store.appIconPlacement = .dock
        XCTAssertTrue(model.canUndo)
        XCTAssertFalse(model.hasExternalChangeNotice)
    }

    func testSlotResetUsesDesignerDefaultAndOnlyClearsItsAuxiliaryFields() {
        let name = "IconDesignerEditorModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        store.airPodsIconDeviceAddress = "10:20:30:40:50:60"
        store.connectedBluetoothIconDeviceAddress = "01:02:03:04:05:06"
        store.bluetoothNetworkIconDeviceAddress = "02:03:04:05:06:07"
        store.refreshesAirPodsBatteryForIcon = true
        let model = IconDesignerEditorModel(store: store)
        model.reset(.center)
        XCTAssertEqual(store.iconConfiguration.composition.center.primary, .network)
        XCTAssertNil(store.connectedBluetoothIconDeviceAddress)
        XCTAssertNil(store.bluetoothNetworkIconDeviceAddress)
        XCTAssertEqual(store.airPodsIconDeviceAddress, "10:20:30:40:50:60")
        XCTAssertTrue(store.refreshesAirPodsBatteryForIcon)
        model.undo()
        XCTAssertEqual(store.connectedBluetoothIconDeviceAddress, "01:02:03:04:05:06")
    }

    func testCenterResetSetsUnifiedSizeAndUndoRestoresLegacyNil() {
        let name = "IconDesignerEditorModelTests.CenterReset.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        store.updateIconConfiguration {
            $0.composition.center = SlotSelection(primary: .bluetoothAudioOutput, fallback: .network)
            $0.appearance.center.effectiveSymbolScale = 4.25
        }
        let model = IconDesignerEditorModel(store: store)

        model.reset(.center)

        XCTAssertEqual(store.iconConfiguration.composition.center.primary, .network)
        XCTAssertEqual(store.iconConfiguration.appearance.center.normalizedSizePercentage, 1.0)
        model.undo()
        XCTAssertEqual(store.iconConfiguration.composition.center.primary, .bluetoothAudioOutput)
        XCTAssertNil(store.iconConfiguration.appearance.center.normalizedSizePercentage)
        XCTAssertEqual(store.iconConfiguration.appearance.center.effectiveSymbolScale, 4.25)
    }

    func testGlobalNetworkOverrideEditIsOneUndoAndSurvivesSourceSwitch() {
        let name = "IconDesignerEditorModelTests.GlobalOverride.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        store.updateIconConfiguration { $0.composition.center = SlotSelection(primary: .network) }
        // Start the designer editing session after the setup source change.
        let editingModel = IconDesignerEditorModel(store: store)

        editingModel.updateIconConfiguration {
            $0.composition.centerOverride.networkProblemOverridesPrimary = true
        }
        XCTAssertEqual(editingModel.historyCountForTesting, 1)
        XCTAssertTrue(store.iconConfiguration.composition.centerOverride.networkProblemOverridesPrimary)

        // Switching the source inside the designer keeps the global rule.
        editingModel.updateIconConfiguration {
            $0.composition.center = SlotSelection(primary: .systemBatteryPercentage)
        }
        XCTAssertTrue(store.iconConfiguration.composition.centerOverride.networkProblemOverridesPrimary)

        // One undo reverses the source switch; the global rule is a separate entry.
        editingModel.undo()
        XCTAssertEqual(store.iconConfiguration.composition.center.primary, .network)
        XCTAssertTrue(store.iconConfiguration.composition.centerOverride.networkProblemOverridesPrimary)
        editingModel.undo()
        XCTAssertFalse(store.iconConfiguration.composition.centerOverride.networkProblemOverridesPrimary)
    }

    func testBluetoothIconChoiceIsUndoableAndResetRevertsToAutomatic() {
        let name = "IconDesignerEditorModelTests.IconChoice.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        let model = IconDesignerEditorModel(store: store)
        store.updateIconConfiguration { $0.composition.center = SlotSelection(primary: .bluetoothAudioOutput) }

        model.perform { store.bluetoothAudioIconChoice = .airpods }
        XCTAssertEqual(store.bluetoothAudioIconChoice, .airpods)

        model.undo()
        XCTAssertEqual(store.bluetoothAudioIconChoice, .automatic)

        model.perform { store.bluetoothAudioIconChoice = .headphones }
        model.reset(.center)
        XCTAssertEqual(store.bluetoothAudioIconChoice, .automatic)
        model.undo()
        XCTAssertEqual(store.bluetoothAudioIconChoice, .headphones)
    }

    func testResetIsUndoableAndPreviewSessionSamplesNeverEnterHistory() {
        let name = "IconDesignerEditorModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        let model = IconDesignerEditorModel(store: store)
        let session = IconDesignerPreviewSession()
        let initialHistoryCount = model.historyCountForTesting

        session.applyAirPodsPreset(.leftOnly)
        XCTAssertEqual(model.historyCountForTesting, initialHistoryCount)
        model.updateIconConfiguration { IconDesignerEditingModel.settingEffectiveCenterScale(2, in: &$0) }
        model.resetAll()
        XCTAssertEqual(store.iconConfiguration.composition.center.primary, .network)
        XCTAssertNil(store.iconConfiguration.composition.center.fallback)
        XCTAssertEqual(store.iconConfiguration.appearance.center.normalizedSizePercentage, 1.0)
        var sourceSwitched = store.iconConfiguration
        for source in [CenterSource.bluetoothAudioOutput, .network] {
            XCTAssertTrue(IconDesignerEditingModel.setPrimary(.center(source), for: .center, in: &sourceSwitched))
            XCTAssertEqual(sourceSwitched.appearance.center.normalizedSizePercentage, 1.0)
        }
        model.undo()
        XCTAssertEqual(store.iconConfiguration.appearance.center.effectiveSymbolScale, 2)
        XCTAssertNil(store.iconConfiguration.appearance.center.normalizedSizePercentage)
    }

    func testAirPodsTopSymbolEditAndOuterRingResetAreUndoable() {
        let name = "IconDesignerEditorModelTests.AirPodsTopSymbol.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        let model = IconDesignerEditorModel(store: store)

        model.updateIconConfiguration { $0.behaviors.showsAirPodsTopSymbol = true }
        XCTAssertTrue(store.iconConfiguration.behaviors.showsAirPodsTopSymbol)
        model.undo()
        XCTAssertFalse(store.iconConfiguration.behaviors.showsAirPodsTopSymbol)

        model.updateIconConfiguration { $0.behaviors.showsAirPodsTopSymbol = true }
        model.reset(.outerRing)
        XCTAssertFalse(store.iconConfiguration.behaviors.showsAirPodsTopSymbol)
        model.undo()
        XCTAssertTrue(store.iconConfiguration.behaviors.showsAirPodsTopSymbol)
    }

}
