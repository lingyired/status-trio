import XCTest
@testable import StatusTrioCore

/// The popover footer shows the settings button and, at the trailing edge, the
/// "more actions" menu. The running version now lives in the standard About
/// panel, so these pin the button label and keep the version from drifting back
/// into it.
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
        // The version now lives in the standard About panel (#191); it must not
        // be folded into the button label, which has to stay short and readable
        // in every language.
        let label = PopoverFooterPresentation.settingsLabel(
            title: "Settings…",
            developmentSuffix: "Apple Link"
        )

        XCTAssertFalse(label.contains("Development"))
        XCTAssertFalse(label.contains("1.3.0"))
    }
}
