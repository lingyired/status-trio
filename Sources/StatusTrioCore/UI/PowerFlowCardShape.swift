import SwiftUI

/// A power-flow card whose edge against a live ribbon is squared while the
/// outer corners stay rounded.
///
/// The battery details flow diagram starts each card as a 12pt rounded
/// rectangle. When a real ribbon reaches a card it should read as one continuous
/// stream, so only the two corners on the connecting edge are square; a card
/// with no live ribbon keeps all four corners rounded.
///
/// This is a custom `Shape` rather than a masked or clipped `RoundedRectangle`
/// so it works on macOS 13 and a single outline backs both the fill and the 1pt
/// rim (`InsettableShape` keeps that rim concentric). The card size, palette and
/// the power-branch proportions are untouched.
struct PowerFlowCardShape: Shape {
    /// Which edge carries a live power-flow ribbon. Only that edge is squared.
    enum Connection: Equatable, Sendable {
        /// No live ribbon: all four corners rounded.
        case none
        /// Fed from the left (a branch card): left corners square.
        case leading
        /// Feeds to the right (the input card): right corners square.
        case trailing
    }

    var connection: Connection
    var cornerRadius: CGFloat
    private var insetAmount: CGFloat

    init(connection: Connection, cornerRadius: CGFloat = 12) {
        self.connection = connection
        self.cornerRadius = cornerRadius
        self.insetAmount = 0
    }

    func inset(by amount: CGFloat) -> PowerFlowCardShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    /// The input card feeds the ribbon on its right; a branch card is fed from
    /// the left. A card with no live ribbon gets no squared corners.
    static func inputConnection(connected: Bool) -> Connection {
        connected ? .trailing : .none
    }

    static func branchConnection(connected: Bool) -> Connection {
        connected ? .leading : .none
    }

    func path(in rect: CGRect) -> Path {
        let bounds = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = max(0, min(cornerRadius - insetAmount,
                                min(bounds.width, bounds.height) / 2))
        let topLeft = connection == .leading ? 0 : radius
        let bottomLeft = connection == .leading ? 0 : radius
        let topRight = connection == .trailing ? 0 : radius
        let bottomRight = connection == .trailing ? 0 : radius

        var path = Path()
        path.move(to: CGPoint(x: bounds.minX + topLeft, y: bounds.minY))
        addCorner(&path, radius: topRight,
                  corner: CGPoint(x: bounds.maxX, y: bounds.minY),
                  next: CGPoint(x: bounds.maxX, y: bounds.maxY))
        addCorner(&path, radius: bottomRight,
                  corner: CGPoint(x: bounds.maxX, y: bounds.maxY),
                  next: CGPoint(x: bounds.minX, y: bounds.maxY))
        addCorner(&path, radius: bottomLeft,
                  corner: CGPoint(x: bounds.minX, y: bounds.maxY),
                  next: CGPoint(x: bounds.minX, y: bounds.minY))
        addCorner(&path, radius: topLeft,
                  corner: CGPoint(x: bounds.minX, y: bounds.minY),
                  next: CGPoint(x: bounds.midX, y: bounds.minY))
        path.closeSubpath()
        return path
    }

    private func addCorner(_ path: inout Path, radius: CGFloat, corner: CGPoint, next: CGPoint) {
        if radius > 0 {
            path.addArc(tangent1End: corner, tangent2End: next, radius: radius)
        } else {
            path.addLine(to: corner)
        }
    }
}

extension PowerFlowCardShape: InsettableShape {}

/// Which card edges, for one diagram snapshot, are squared because a real
/// (non-hairline) ribbon reaches them. Ribbons below the drawing floor are not
/// drawn at all, so their cards must stay fully rounded instead of squaring a
/// corner against nothing.
struct PowerFlowCardConnections: Equatable, Sendable {
    /// Ribbons at or below this thickness are filtered out of the drawing.
    static let liveThreshold: CGFloat = 0.5

    let inputConnected: Bool
    let branches: [Bool]

    init(hasInput: Bool, branchThicknesses: [CGFloat]) {
        let live = branchThicknesses.map { $0 > Self.liveThreshold }
        branches = live
        inputConnected = hasInput && live.contains(true)
    }
}

extension View {
    /// Paints a power-flow card surface: a single-side-rounded fill, a 1pt rim
    /// from the same outline, and — when the card connects — a 1pt tab of the
    /// fill lapped under the connecting edge so anti-aliasing cannot leave a
    /// hairline seam against the ribbon.
    func powerFlowCardSurface(
        fill: Color,
        stroke: Color,
        connection: PowerFlowCardShape.Connection
    ) -> some View {
        modifier(PowerFlowCardSurfaceModifier(fill: fill, stroke: stroke, connection: connection))
    }
}

private struct PowerFlowCardSurfaceModifier: ViewModifier {
    let fill: Color
    let stroke: Color
    let connection: PowerFlowCardShape.Connection

    func body(content: Content) -> some View {
        let shape = PowerFlowCardShape(connection: connection)
        content
            .background(shape.fill(fill))
            .background(alignment: connection == .trailing ? .trailing : .leading) {
                if connection != .none {
                    Rectangle()
                        .fill(fill)
                        .frame(width: 2)
                        .offset(x: connection == .trailing ? 1 : -1)
                }
            }
            .overlay {
                shape.strokeBorder(stroke, lineWidth: 1)
            }
    }
}
