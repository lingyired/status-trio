import XCTest
@testable import StatusTrioCore

final class MenuBarInstanceActivationTests: XCTestCase {
    func testPanelMaps() {
        XCTAssertEqual(
            MenuBarInstanceActivationResolver.resolve(.panel("cpu"), forHover: false),
            .showPanel(routeRaw: "cpu")
        )
    }

    func testHoverRejectsExternalActions() {
        XCTAssertEqual(MenuBarInstanceActivationResolver.resolve(.openAppSettings, forHover: true), .noop)
        XCTAssertEqual(MenuBarInstanceActivationResolver.resolve(.openActivityMonitor, forHover: true), .noop)
        XCTAssertEqual(MenuBarInstanceActivationResolver.resolve(.openSystemSettings(.wifi), forHover: true), .noop)
        XCTAssertEqual(MenuBarInstanceActivationResolver.resolve(.panel("summary"), forHover: true), .showPanel(routeRaw: "summary"))
    }

    func testLeftAllowsExternal() {
        XCTAssertEqual(MenuBarInstanceActivationResolver.resolve(.openActivityMonitor, forHover: false), .openActivityMonitor)
        XCTAssertEqual(MenuBarInstanceActivationResolver.resolve(.openSystemSettings(.bluetooth), forHover: false), .openSystemSettings(.bluetooth))
    }

    func testSameAsMainIcon() {
        XCTAssertEqual(MenuBarInstanceActivationResolver.resolve(.sameAsMainIcon, forHover: false), .followMainIcon)
        XCTAssertEqual(MenuBarInstanceActivationResolver.resolve(.sameAsMainIcon, forHover: true), .followMainIcon)
    }

    func testNone() {
        XCTAssertEqual(MenuBarInstanceActivationResolver.resolve(.none, forHover: false), .noop)
    }
}
