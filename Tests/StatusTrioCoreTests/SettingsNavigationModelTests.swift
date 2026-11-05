import XCTest
@testable import StatusTrioCore

@MainActor
final class SettingsNavigationModelTests: XCTestCase {
    func testInitialSelectionIsAppIconAppearance() {
        let model = SettingsNavigationModel()
        XCTAssertEqual(model.selectedSection, .appIcon)
        XCTAssertEqual(model.expandedSection, .appIcon)
        XCTAssertEqual(model.selectedSubtopic, .appIconAppearance)
    }

    func testSelectingComplexCategoryOpensItsDefaultLeaf() {
        let model = SettingsNavigationModel()
        model.select(.battery)
        XCTAssertEqual(model.selectedSection, .battery)
        XCTAssertEqual(model.expandedSection, .battery)
        XCTAssertEqual(model.selectedSubtopic, .batteryCharging)

        model.select(.audio)
        XCTAssertEqual(model.selectedSubtopic, .audioVolumeControl)
        model.select(.bluetooth)
        XCTAssertEqual(model.selectedSubtopic, .bluetoothListeningMode)
    }

    func testOnlyOneCategoryStaysExpanded() {
        let model = SettingsNavigationModel()
        model.select(.battery)
        XCTAssertEqual(model.expandedSection, .battery)
        model.select(.audio)
        XCTAssertEqual(model.expandedSection, .audio, "selecting another category collapses the old one")
    }

    func testSelectingSimpleCategoryCollapsesAndClearsLeaf() {
        let model = SettingsNavigationModel()
        model.select(.network)
        XCTAssertEqual(model.selectedSection, .network)
        XCTAssertNil(model.expandedSection)
        XCTAssertNil(model.selectedSubtopic)
    }

    func testSelectSubtopicExpandsParentAndSetsSection() {
        let model = SettingsNavigationModel()
        model.select(.battery)
        model.selectSubtopic(.batteryPowerMode)
        XCTAssertEqual(model.selectedSection, .battery)
        XCTAssertEqual(model.expandedSection, .battery)
        XCTAssertEqual(model.selectedSubtopic, .batteryPowerMode)
    }

    func testRememberedLeafIsRestoredWhenReenteringACategory() {
        let model = SettingsNavigationModel()
        model.select(.battery)
        model.selectSubtopic(.batteryEnergy)
        model.select(.network)
        model.select(.battery)
        XCTAssertEqual(
            model.selectedSubtopic,
            .batteryEnergy,
            "re-entering a category should return to the leaf the user last viewed"
        )
    }

    func testApplyOpensTheRequestedLeaf() {
        let model = SettingsNavigationModel()
        model.apply(section: .battery, subtopic: .batteryCharging)
        XCTAssertEqual(model.selectedSection, .battery)
        XCTAssertEqual(model.selectedSubtopic, .batteryCharging)
    }

    func testApplyFallsBackToDefaultWhenLeafBelongsToAnotherCategory() {
        let model = SettingsNavigationModel()
        model.apply(section: .audio, subtopic: .batteryCharging)
        XCTAssertEqual(model.selectedSection, .audio)
        XCTAssertEqual(
            model.selectedSubtopic,
            .audioVolumeControl,
            "a stale leaf must never render the wrong category's page"
        )
    }

    func testApplyWithoutLeafOpensTheCategoryDefault() {
        let model = SettingsNavigationModel()
        model.apply(section: .bluetooth, subtopic: nil)
        XCTAssertEqual(model.selectedSection, .bluetooth)
        XCTAssertEqual(model.selectedSubtopic, .bluetoothListeningMode)
    }

    func testSectionSubtopicsMatchTheLeafOwnership() {
        XCTAssertTrue(SettingsView.Section.network.subtopics.isEmpty)
        XCTAssertTrue(SettingsView.Section.brightness.subtopics.isEmpty)
        XCTAssertTrue(SettingsView.Section.popover.subtopics.isEmpty)
        XCTAssertTrue(SettingsView.Section.general.subtopics.isEmpty)
        XCTAssertTrue(SettingsView.Section.about.subtopics.isEmpty)

        XCTAssertEqual(
            SettingsView.Section.appIcon.subtopics,
            [.appIconAppearance, .appIconRing, .appIconMiddleIcon, .appIconBottomIndicator]
        )
        XCTAssertEqual(
            SettingsView.Section.battery.subtopics,
            [.batteryCharging, .batteryPowerMode, .batteryEnergy]
        )
        XCTAssertEqual(
            SettingsView.Section.audio.subtopics,
            [.audioVolumeControl, .audioAudioDevices, .audioDisplayVolume]
        )
        XCTAssertEqual(
            SettingsView.Section.bluetooth.subtopics,
            [.bluetoothListeningMode, .bluetoothDeviceBattery, .bluetoothDeviceManagement]
        )
        XCTAssertTrue(SettingsView.Section.battery.hasSubtopics)
    }
}
