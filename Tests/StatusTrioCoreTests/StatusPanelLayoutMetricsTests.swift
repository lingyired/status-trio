import XCTest
@testable import StatusTrioCore

@MainActor
final class StatusPanelLayoutMetricsTests: XCTestCase {
    func testReplacingAHostRejectsItsLateNaturalHeightMeasurement() {
        let metrics = StatusPanelLayoutMetrics()
        let oldHost = UUID()
        let newHost = UUID()
        var oldHeights: [CGFloat] = []
        var newHeights: [CGFloat] = []
        metrics.attachWindow(measurementID: oldHost) { oldHeights.append($0) }
        metrics.measure(contentHeight: 120, from: oldHost)
        metrics.attachWindow(measurementID: newHost) { newHeights.append($0) }
        metrics.measure(contentHeight: 240, from: newHost)

        // A retained old SwiftUI preference and an unbound fallback must both
        // leave the current host's measurement and window callback untouched.
        metrics.measure(contentHeight: 600, from: oldHost)
        metrics.measure(contentHeight: 700)
        XCTAssertEqual(metrics.contentHeight, 240)
        XCTAssertEqual(oldHeights, [120])
        XCTAssertEqual(newHeights, [240])
    }

    func testOnlyDistinctValidMeasurementsReachTheWindow() {
        let metrics = StatusPanelLayoutMetrics()
        var heights: [CGFloat] = []
        metrics.attachWindow { heights.append($0) }
        for height: CGFloat in [0, -.infinity, .infinity, .nan, 120, 120, 160] {
            metrics.measure(contentHeight: height)
        }
        XCTAssertEqual(heights, [120, 160])
        XCTAssertEqual(metrics.contentHeight, 160)
    }
}
