import XCTest
@testable import StatusTrioCore

@MainActor
final class SettingsNavigationModelTests: XCTestCase {
    func testInitialSelectionIsAppIconPlacement() {
        let model = SettingsNavigationModel()
        XCTAssertEqual(model.selectedSection, .appIcon)
        XCTAssertEqual(model.expandedSection, .appIcon)
        XCTAssertEqual(model.selectedSubtopic, .appIconPlacementSize)
    }

    func testSelectingComplexCategoryOpensItsDefaultLeaf() {
        let model = SettingsNavigationModel()
        model.select(.battery)
        XCTAssertEqual(model.selectedSection, .battery)
        XCTAssertEqual(model.expandedSection, .battery)
        XCTAssertEqual(model.selectedSubtopic, .batteryIconDisplay)

        model.select(.audio)
        XCTAssertEqual(model.selectedSubtopic, .audioDisplayAndInteraction)
        model.select(.bluetooth)
        XCTAssertEqual(model.selectedSubtopic, .bluetoothDisplayAndPreview)
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
        model.selectSubtopic(.batteryChargeManagement)
        XCTAssertEqual(model.selectedSection, .battery)
        XCTAssertEqual(model.expandedSection, .battery)
        XCTAssertEqual(model.selectedSubtopic, .batteryChargeManagement)
    }

    func testRememberedLeafIsRestoredWhenReenteringACategory() {
        let model = SettingsNavigationModel()
        model.select(.battery)
        model.selectSubtopic(.batteryPowerAndEnergy)
        model.select(.network)
        model.select(.battery)
        XCTAssertEqual(
            model.selectedSubtopic,
            .batteryPowerAndEnergy,
            "re-entering a category should return to the leaf the user last viewed"
        )
    }

    func testApplyOpensTheRequestedLeaf() {
        let model = SettingsNavigationModel()
        model.apply(section: .battery, subtopic: .batteryChargeManagement)
        XCTAssertEqual(model.selectedSection, .battery)
        XCTAssertEqual(model.selectedSubtopic, .batteryChargeManagement)
    }

    func testApplyFallsBackToDefaultWhenLeafBelongsToAnotherCategory() {
        let model = SettingsNavigationModel()
        model.apply(section: .audio, subtopic: .batteryChargeManagement)
        XCTAssertEqual(model.selectedSection, .audio)
        XCTAssertEqual(
            model.selectedSubtopic,
            .audioDisplayAndInteraction,
            "a stale leaf must never render the wrong category's page"
        )
    }

    func testApplyWithoutLeafOpensTheCategoryDefault() {
        let model = SettingsNavigationModel()
        model.apply(section: .bluetooth, subtopic: nil)
        XCTAssertEqual(model.selectedSection, .bluetooth)
        XCTAssertEqual(model.selectedSubtopic, .bluetoothDisplayAndPreview)
    }

    func testSectionSubtopicsMatchTheLeafOwnership() {
        XCTAssertTrue(SettingsView.Section.network.subtopics.isEmpty)
        XCTAssertTrue(SettingsView.Section.brightness.subtopics.isEmpty)
        XCTAssertTrue(SettingsView.Section.popover.subtopics.isEmpty)
        XCTAssertTrue(SettingsView.Section.general.subtopics.isEmpty)
        XCTAssertTrue(SettingsView.Section.about.subtopics.isEmpty)

        XCTAssertEqual(
            SettingsView.Section.battery.subtopics,
            [.batteryIconDisplay, .batteryColorsAndAnimation, .batteryChargeManagement, .batteryPowerAndEnergy]
        )
        XCTAssertTrue(SettingsView.Section.battery.hasSubtopics)
    }
}
