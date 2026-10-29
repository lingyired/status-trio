import XCTest
@testable import StatusTrioCore

final class DevelopmentBuildPresentationTests: XCTestCase {
    func testAboutSidebarDetailAddsCodenameAfterVersion() {
        XCTAssertEqual(
            DevelopmentBuildPresentation.aboutSidebarDetail(
                version: "1.7.5 (43)",
                codename: "Charge To Full Now"
            ),
            "v1.7.5 (43)\nCharge To Full Now"
        )
    }

    func testAboutSidebarDetailOmitsMissingOrEmptyCodename() {
        XCTAssertEqual(
            DevelopmentBuildPresentation.aboutSidebarDetail(
                version: "1.7.5 (43)",
                codename: nil
            ),
            "v1.7.5 (43)"
        )
        XCTAssertEqual(
            DevelopmentBuildPresentation.aboutSidebarDetail(
                version: "1.7.5 (43)",
                codename: ""
            ),
            "v1.7.5 (43)"
        )
    }
}
