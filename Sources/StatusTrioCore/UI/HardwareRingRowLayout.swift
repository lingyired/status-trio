import SwiftUI

/// Lays the visible ring cards across the full width in equal columns, so two
/// remaining rings each take half the width and three each take a third. The
/// card height stays at the four-column square size, so the row never grows
/// taller, and the ring is centred inside its (wider) card.
struct HardwareRingRowLayout: Layout {
    var spacing: CGFloat = 6
    var referenceCount: Int = HardwareRingSlot.allCases.count

    /// The square side a card would have in the full four-column layout. Used as
    /// the fixed card height so the ring diameter stays constant.
    private func referenceSide(for width: CGFloat) -> CGFloat {
        let columns = CGFloat(max(1, referenceCount))
        return max(0, (width - spacing * (columns - 1)) / columns)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        return CGSize(width: width, height: referenceSide(for: width))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let count = subviews.count
        guard count > 0 else { return }
        let side = referenceSide(for: bounds.width)
        let column = max(0, (bounds.width - spacing * CGFloat(count - 1)) / CGFloat(count))
        var x = bounds.minX
        for subview in subviews {
            subview.place(at: CGPoint(x: x, y: bounds.minY),
                          anchor: .topLeading,
                          proposal: ProposedViewSize(width: column, height: side))
            x += column + spacing
        }
    }
}
