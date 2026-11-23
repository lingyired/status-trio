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

    func testSelectingAppIconOpensItsDefaultLeaf() {
        let model = SettingsNavigationModel()
        model.select(.appIcon)
        XCTAssertEqual(model.selectedSection, .appIcon)
        XCTAssertEqual(model.expandedSection, .appIcon)
        XCTAssertEqual(model.selectedSubtopic, .appIconAppearance)
    }

    func testBatteryAudioAndBluetoothAreSinglePane() {
        let model = SettingsNavigationModel()
        for section in [SettingsView.Section.battery, .audio, .bluetooth] {
            model.select(section)
            XCTAssertEqual(model.selectedSection, section)
            XCTAssertEqual(model.expandedSection, .appIcon, "App Icon stays expanded")
            XCTAssertNil(model.selectedSubtopic, "\(section) has no leaf subtopic")
        }
    }

    func testAppIconStaysExpandedWhenSwitchingCategories() {
        let model = SettingsNavigationModel()
        model.select(.appIcon)
        model.selectSubtopic(.appIconRing)
        XCTAssertEqual(model.expandedSection, .appIcon)
        model.select(.network)
        XCTAssertEqual(model.expandedSection, .appIcon, "the only submenu never collapses")
        model.select(.battery)
        XCTAssertEqual(model.expandedSection, .appIcon)
    }

    func testSelectingSimpleCategoryKeepsAppIconExpanded() {
        let model = SettingsNavigationModel()
        model.select(.network)
        XCTAssertEqual(model.selectedSection, .network)
        XCTAssertEqual(model.expandedSection, .appIcon, "App Icon keeps its submenu visible")
        XCTAssertNil(model.selectedSubtopic)
    }

    func testSelectSubtopicExpandsParentAndSetsSection() {
        let model = SettingsNavigationModel()
        model.selectSubtopic(.appIconBottomIndicator)
        XCTAssertEqual(model.selectedSection, .appIcon)
        XCTAssertEqual(model.expandedSection, .appIcon)
        XCTAssertEqual(model.selectedSubtopic, .appIconBottomIndicator)
    }

    func testRememberedLeafIsRestoredWhenReenteringACategory() {
        let model = SettingsNavigationModel()
        model.selectSubtopic(.appIconMiddleIcon)
        model.select(.network)
        model.select(.appIcon)
        XCTAssertEqual(
            model.selectedSubtopic,
            .appIconMiddleIcon,
            "re-entering a category should return to the leaf the user last viewed"
        )
    }

    func testApplyOpensTheRequestedLeaf() {
        let model = SettingsNavigationModel()
        model.apply(section: .appIcon, subtopic: .appIconRing)
        XCTAssertEqual(model.selectedSection, .appIcon)
        XCTAssertEqual(model.selectedSubtopic, .appIconRing)
    }

    func testApplyFallsBackToDefaultWhenLeafBelongsToAnotherCategory() {
        let model = SettingsNavigationModel()
        model.apply(section: .audio, subtopic: .appIconRing)
        XCTAssertEqual(model.selectedSection, .audio)
        XCTAssertNil(
            model.selectedSubtopic,
            "a stale leaf must never render the wrong category's page"
        )
    }

    func testApplyWithoutLeafOpensTheCategoryDefault() {
        let model = SettingsNavigationModel()
        model.apply(section: .appIcon, subtopic: nil)
        XCTAssertEqual(model.selectedSection, .appIcon)
        XCTAssertEqual(model.selectedSubtopic, .appIconAppearance)
    }

    func testSectionSubtopicsMatchTheLeafOwnership() {
        XCTAssertTrue(SettingsView.Section.network.subtopics.isEmpty)
        XCTAssertTrue(SettingsView.Section.brightness.subtopics.isEmpty)
        XCTAssertTrue(SettingsView.Section.popover.subtopics.isEmpty)
        XCTAssertTrue(SettingsView.Section.general.subtopics.isEmpty)
        XCTAssertTrue(SettingsView.Section.about.subtopics.isEmpty)
        XCTAssertTrue(SettingsView.Section.battery.subtopics.isEmpty)
        XCTAssertTrue(SettingsView.Section.audio.subtopics.isEmpty)
        XCTAssertTrue(SettingsView.Section.bluetooth.subtopics.isEmpty)

        XCTAssertEqual(
            SettingsView.Section.appIcon.subtopics,
            [.appIconAppearance, .appIconRing, .appIconMiddleIcon, .appIconBottomIndicator]
        )
        XCTAssertTrue(SettingsView.Section.appIcon.hasSubtopics)
    }
}
