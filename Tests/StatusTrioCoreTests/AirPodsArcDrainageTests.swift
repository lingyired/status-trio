import CoreGraphics
import Testing
@testable import StatusTrioCore

struct AirPodsArcDrainageTests {
    @Test
    func equalProgressEndpointsAreHorizontalMirrors() {
        for progress in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let left = StatusIconGeometry.airPodsArc(position: .left, progress: progress)
            let right = StatusIconGeometry.airPodsArc(position: .right, progress: progress)

            if progress == 0 {
                #expect(left.isEmpty)
                #expect(right.isEmpty)
                continue
            }

            let leftEndpoint = left.currentPoint
            let rightEndpoint = right.currentPoint
            let leftBounds = left.boundingBox
            let rightBounds = right.boundingBox
            #expect(abs(leftEndpoint.x + rightEndpoint.x - 2 * StatusIconGeometry.artworkCenterX) < 0.001)
            #expect(abs(leftEndpoint.y - rightEndpoint.y) < 0.001)
            #expect(abs(leftBounds.minX + rightBounds.maxX - 2 * StatusIconGeometry.artworkCenterX) < 0.001)
            #expect(abs(leftBounds.maxX + rightBounds.minX - 2 * StatusIconGeometry.artworkCenterX) < 0.001)
            #expect(abs(leftBounds.minY - rightBounds.minY) < 0.001)
            #expect(abs(leftBounds.maxY - rightBounds.maxY) < 0.001)
        }
    }

    @Test
    func depletionExpandsDownwardFromAStableBottomAnchor() {
        let progressValues = [0.25, 0.5, 0.75, 1.0]

        for position in [RingSegmentPosition.left, .right] {
            let paths = progressValues.map {
                StatusIconGeometry.airPodsArc(position: position, progress: $0)
            }
            let bounds = paths.map(\.boundingBox)

            #expect(bounds.allSatisfy { !$0.isNull })
            #expect(bounds[0].minY > bounds[1].minY)
            #expect(bounds[1].minY > bounds[2].minY)
            #expect(bounds[2].minY > bounds[3].minY)
            #expect(bounds.dropFirst().allSatisfy { abs($0.maxY - bounds[0].maxY) < 0.001 })
        }
    }
}
