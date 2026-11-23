import Foundation
import XCTest

enum VisibleUITests {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["STATUS_TRIO_ALLOW_VISIBLE_UI_TESTS"] == "1"
    }

    static let reason =
        "Requires visible AppKit UI. Run only in an authorized session with STATUS_TRIO_ALLOW_VISIBLE_UI_TESTS=1."
}

/// These fixtures create real windows or menu-bar items; a policy spy alone
/// does not prevent their presentation methods from changing the desktop.
class VisibleUITestCase: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(VisibleUITests.isEnabled, VisibleUITests.reason)
    }
}
