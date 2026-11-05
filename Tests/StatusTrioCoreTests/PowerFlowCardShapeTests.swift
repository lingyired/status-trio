import CoreGraphics
import SwiftUI
import Testing
@testable import StatusTrioCore

/// Issue #282: the power-flow cards must meet their ribbon flush. Only the
/// corner(s) on the edge a real ribbon reaches are squared; every other corner
/// stays at the 12pt radius, and a card with no live ribbon keeps all four
/// rounded. These tests read the actual `Path` geometry instead of restating a
/// constant, so a wrong corner or a mask/clip that leaves the shape rounded
/// fails here.
@MainActor
struct PowerFlowCardShapeTests {
    private let card = CGRect(x: 0, y: 0, width: 94, height: 40)

    /// A point one point inside each corner. For a 12pt rounded corner that
    /// point is outside the filled shape (its distance to the corner centre is
    /// ~15.6pt); for a squared corner it is inside.
    private func nearCorners(_ rect: CGRect)
        -> (topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint, bottomRight: CGPoint) {
        let d: CGFloat = 1
        return (
            CGPoint(x: rect.minX + d, y: rect.minY + d),
            CGPoint(x: rect.maxX - d, y: rect.minY + d),
            CGPoint(x: rect.minX + d, y: rect.maxY - d),
            CGPoint(x: rect.maxX - d, y: rect.maxY - d)
        )
    }

    private func expectBounds(_ path: Path, equals rect: CGRect) {
        #expect(abs(path.boundingRect.minX - rect.minX) < 0.01)
        #expect(abs(path.boundingRect.minY - rect.minY) < 0.01)
        #expect(abs(path.boundingRect.maxX - rect.maxX) < 0.01)
        #expect(abs(path.boundingRect.maxY - rect.maxY) < 0.01)
    }

    @Test func isolatedCardKeepsAllFourCornersRounded() {
        let path = PowerFlowCardShape(connection: .none).path(in: card)
        expectBounds(path, equals: card)
        let corners = nearCorners(card)
        #expect(!path.contains(corners.topLeft))
        #expect(!path.contains(corners.topRight))
        #expect(!path.contains(corners.bottomLeft))
        #expect(!path.contains(corners.bottomRight))
        #expect(path.contains(CGPoint(x: card.midX, y: card.midY)))
    }

    @Test func trailingConnectionSquaresTheRightCorners() {
        let path = PowerFlowCardShape(connection: .trailing).path(in: card)
        expectBounds(path, equals: card)
        let corners = nearCorners(card)
        #expect(!path.contains(corners.topLeft), "left corners stay rounded")
        #expect(path.contains(corners.topRight), "the ribbon-side top corner is square")
        #expect(!path.contains(corners.bottomLeft), "left corners stay rounded")
        #expect(path.contains(corners.bottomRight), "the ribbon-side bottom corner is square")
    }

    @Test func leadingConnectionSquaresTheLeftCorners() {
        let path = PowerFlowCardShape(connection: .leading).path(in: card)
        expectBounds(path, equals: card)
        let corners = nearCorners(card)
        #expect(path.contains(corners.topLeft), "the ribbon-side top corner is square")
        #expect(!path.contains(corners.topRight), "right corners stay rounded")
        #expect(path.contains(corners.bottomLeft), "the ribbon-side bottom corner is square")
        #expect(!path.contains(corners.bottomRight), "right corners stay rounded")
    }

    @Test func insetRimStaysConcentricAndKeepsTheConnectionSquare() {
        let inset: CGFloat = 0.5
        let path = PowerFlowCardShape(connection: .trailing).inset(by: inset).path(in: card)
        expectBounds(path, equals: card.insetBy(dx: inset, dy: inset))
        let inner = card.insetBy(dx: inset, dy: inset)
        let corners = nearCorners(inner)
        #expect(!path.contains(corners.topLeft))
        #expect(path.contains(corners.topRight))
    }

    @Test func onlyEdgesWithALiveRibbonAreConnected() {
        let live = PowerFlowCardConnections(hasInput: true, branchThicknesses: [10, 6])
        #expect(live.inputConnected)
        #expect(live.branches == [true, true])

        // A hairline or absent ribbon draws nothing, so it must not square a
        // card corner in mid-air.
        let hairline = PowerFlowCardConnections(hasInput: true, branchThicknesses: [0, 0.5, 0.49])
        #expect(!hairline.inputConnected)
        #expect(hairline.branches == [false, false, false])

        // No input card (a legacy snapshot) never squares the input edge even if
        // a branch is somehow live.
        let noInput = PowerFlowCardConnections(hasInput: false, branchThicknesses: [12])
        #expect(!noInput.inputConnected)
        #expect(noInput.branches == [true])

        let empty = PowerFlowCardConnections(hasInput: true, branchThicknesses: [])
        #expect(!empty.inputConnected)
        #expect(empty.branches.isEmpty)
    }

    @Test func inputConnectsOnTrailingAndBranchOnLeading() {
        #expect(PowerFlowCardShape.inputConnection(connected: true) == .trailing)
        #expect(PowerFlowCardShape.inputConnection(connected: false) == .none)
        #expect(PowerFlowCardShape.branchConnection(connected: true) == .leading)
        #expect(PowerFlowCardShape.branchConnection(connected: false) == .none)
    }
}
