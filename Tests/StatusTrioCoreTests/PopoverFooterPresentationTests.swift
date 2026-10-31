import XCTest
@testable import StatusTrioCore

/// The popover footer shows the settings button and, at the trailing edge, the
/// running version. These pin the two labels so the version cannot drift back
/// into the button's own text.
final class PopoverFooterPresentationTests: XCTestCase {
    func testSettingsLabelIsTheTitleWithoutACodename() {
        XCTAssertEqual(
            PopoverFooterPresentation.settingsLabel(title: "Settings…", developmentSuffix: nil),
            "Settings…"
        )
    }

    func testSettingsLabelOmitsTheDevelopmentCodename() {
        XCTAssertEqual(
            PopoverFooterPresentation.settingsLabel(
                title: "Settings…",
                developmentSuffix: "Apple Link"
            ),
            "Settings…"
        )
    }

    func testSettingsLabelIgnoresAnEmptyDevelopmentSuffix() {
        XCTAssertEqual(
            PopoverFooterPresentation.settingsLabel(title: "Settings…", developmentSuffix: ""),
            "Settings…"
        )
    }

    func testSettingsLabelNeverCarriesTheVersion() {
        // The version is a separate element at the trailing edge of the row; it
        // must not be folded into the button label, which has to stay short and
        // readable in every language.
        let label = PopoverFooterPresentation.settingsLabel(
            title: "Settings…",
            developmentSuffix: "Apple Link"
        )

        XCTAssertFalse(label.contains("Development"))
        XCTAssertFalse(label.contains("1.3.0"))
    }
}
