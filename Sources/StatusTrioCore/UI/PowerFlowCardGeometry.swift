import SwiftUI

/// Geometry shared by the power-flow ribbons and cards (#282).
///
/// The cards keep their original fully rounded outline. Each ribbon extends
/// underneath them; the ribbon mask clears the card interiors so their
/// translucent fills cannot reveal the overlap.
enum PowerFlowCardGeometry {
    /// How far a ribbon continues under a card.
    static let connectionOverlap: CGFloat = 6
    /// A thinner ribbon is not drawn; the cards it would touch stay untouched.
    static let liveThreshold: CGFloat = 0.5

    /// The ribbon's left end, extended into the input card.
    static func ribbonStartX(inputCardRight: CGFloat) -> CGFloat {
        inputCardRight - connectionOverlap
    }

    /// The ribbon's right end, extended into the branch card.
    static func ribbonEndX(branchCardLeft: CGFloat) -> CGFloat {
        branchCardLeft + connectionOverlap
    }
}

/// Shows the ribbon layer everywhere except inside the rounded cards. The
/// cards are translucent, so painting them above a ribbon alone would leave a
/// dark strip showing through. Cutting out their silhouettes keeps the glass
/// fill unchanged while the exposed ribbons meet the rounded rim.
struct PowerFlowRibbonMask: Shape {
    let cardFrames: [CGRect]

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        for frame in cardFrames {
            path.addPath(RoundedRectangle(cornerRadius: 12).path(in: frame))
        }
        return path
    }
}

extension View {
    /// The original rounded card surface, with fill and rim drawn from the same
    /// rounded outline.
    func powerFlowCardSurface(fill: Color, stroke: Color) -> some View {
        modifier(PowerFlowCardSurfaceModifier(fill: fill, stroke: stroke))
    }
}

private struct PowerFlowCardSurfaceModifier: ViewModifier {
    let fill: Color
    let stroke: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        content
            .background(shape.fill(fill))
            .overlay {
                shape.strokeBorder(stroke, lineWidth: 1)
            }
    }
}
