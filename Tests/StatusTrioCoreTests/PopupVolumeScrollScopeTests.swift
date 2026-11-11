import XCTest
@testable import StatusTrioCore

final class PopupVolumeScrollScopeTests: XCTestCase {
    func testPanelScopeKeepsVolumeAdjustmentOnSummary() {
        XCTAssertTrue(PopupVolumeScrollScope.panel.allowsPanelAdjustment(on: .summary))
    }

    func testPanelScopeDoesNotAdjustVolumeOnDetailPages() {
        let detailRoutes: [StatusPanelRoute] = [.battery, .wifi, .ethernet, .inputSource]

        for route in detailRoutes {
            XCTAssertFalse(
                PopupVolumeScrollScope.panel.allowsPanelAdjustment(on: route),
                "scrolling a \(route) detail page must not change output volume"
            )
        }
    }

    func testSliderOnlyScopeNeverAdjustsVolumeOutsideSliders() {
        let routes: [StatusPanelRoute] = [.summary, .battery, .wifi, .ethernet, .inputSource]

        for route in routes {
            XCTAssertFalse(
                PopupVolumeScrollScope.volumeControl.allowsPanelAdjustment(on: route),
                "slider-only scope must leave non-slider scrolling alone on \(route)"
            )
        }
    }
}
