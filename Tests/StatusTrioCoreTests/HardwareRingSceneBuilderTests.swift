import XCTest
@testable import StatusTrioCore

/// The four status-panel rings reuse the shared ring renderer, so the split-gap
/// option has to reach `OuterRingState.gapProgressMode`. This covers the pure
/// scene mapping without a SwiftUI host (#375).
final class HardwareRingSceneBuilderTests: XCTestCase {
    private let color = IconRGBA(red: 0.2, green: 0.8, blue: 0.4, alpha: 1)

    func testSplitGapProgressOffKeepsAbsorbedGap() {
        let ring = HardwareRingSceneBuilder.outerRing(
            progress: 0.42, color: color, splitGapProgress: false
        )
        XCTAssertEqual(ring.gap, .value)
        XCTAssertEqual(ring.gapProgressMode, .absorbed)
    }

    func testSplitGapProgressOnSelectsSplitGap() {
        let ring = HardwareRingSceneBuilder.outerRing(
            progress: 0.42, color: color, splitGapProgress: true
        )
        XCTAssertEqual(ring.gap, .value)
        XCTAssertEqual(ring.gapProgressMode, .split)
        XCTAssertEqual(ring.segments.count, 1)
        XCTAssertEqual(ring.segments.first?.progress ?? -1, 0.42, accuracy: 0.0001)
        XCTAssertEqual(ring.segments.first?.color, .custom(color))
    }
}
