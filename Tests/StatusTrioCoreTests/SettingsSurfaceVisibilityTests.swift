import XCTest
@testable import StatusTrioCore

final class SettingsSurfaceVisibilityTests: XCTestCase {
    func testClosingSettingsDoesNotHideVisibleDesigner() {
        var visibility = SettingsSurfaceVisibility()
        visibility.setVisible(true, owner: "settings")
        visibility.setVisible(true, owner: "designer")

        visibility.setVisible(false, owner: "settings")
        XCTAssertTrue(visibility.isVisible)
        XCTAssertEqual(visibility.owners, ["designer"])

        visibility.setVisible(false, owner: "designer")
        XCTAssertFalse(visibility.isVisible)
    }

    func testRepeatedVisibilityChangesAreIdempotentAndOwnersCloseInEitherOrder() {
        var visibility = SettingsSurfaceVisibility()
        visibility.setVisible(true, owner: "settings")
        visibility.setVisible(true, owner: "settings")
        visibility.setVisible(true, owner: "designer")
        XCTAssertEqual(visibility.owners, ["settings", "designer"])

        visibility.setVisible(false, owner: "designer")
        XCTAssertTrue(visibility.isVisible)
        visibility.setVisible(false, owner: "settings")
        XCTAssertFalse(visibility.isVisible)

        visibility.setVisible(true, owner: "designer")
        visibility.setVisible(true, owner: "settings")
        visibility.setVisible(false, owner: "settings")
        XCTAssertTrue(visibility.isVisible)
        visibility.setVisible(false, owner: "designer")
        XCTAssertFalse(visibility.isVisible)
    }
}
