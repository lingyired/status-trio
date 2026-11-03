import SwiftUI

/// Height policy for a panel volume-output row, mirroring the layout in
/// `OutputDeviceRow`: a 24-point icon column with 3 points of vertical padding,
/// plus the listening-mode control's own line when one is drawn. Kept next to
/// the skeleton so the placeholder row and the real row cannot drift apart.
enum VolumeDeviceRowMetrics {
    /// The row without a listening-mode control: the icon column plus the row's
    /// own top and bottom padding.
    static let singleLineHeight: CGFloat = 30

    /// The extra height a controllable listening-mode control adds under the
    /// name: the parent stack's 2-point gap plus the capsule's line and padding.
    static let listeningModeExtraHeight: CGFloat = 22

    static func estimatedHeight(for row: PanelAudioDeviceRow) -> CGFloat {
        row.listeningMode?.isControllable == true
            ? singleLineHeight + listeningModeExtraHeight
            : singleLineHeight
    }

    static func rowHeights(for rows: [PanelAudioDeviceRow]) -> [Double] {
        rows.map { Double(estimatedHeight(for: $0)) }
    }
}

/// Static grey bars sized to the rows they stand in for. Drawn only while a
/// device list re-reads its data after the panel reopens, so the panel height
/// does not jump; it is deliberately non-interactive and never animated.
struct PanelListSkeleton: View {
    let rowHeights: [CGFloat]
    var rowSpacing: CGFloat = 2
    /// A row at or above this height is drawn with a second bar (the two-line
    /// or listening-mode rows) so the skeleton reads like the real list.
    var twoLineThreshold: CGFloat = 30

    private static let barColor = Color.secondary.opacity(0.16)

    var body: some View {
        VStack(spacing: rowSpacing) {
            ForEach(Array(rowHeights.enumerated()), id: \.offset) { _, height in
                row(height: height)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func row(height: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Self.barColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Self.barColor)
                    .frame(width: 128, height: 9)
                if height >= twoLineThreshold {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Self.barColor)
                        .frame(width: 76, height: 8)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height, alignment: .leading)
    }
}

/// Stands in for the real expand/collapse control so its height is identical,
/// but is not interactive while the list is still loading.
struct PanelDeviceListExpansionPlaceholder: View {
    @State private var isExpanded = false
    let expandLabel: String
    let collapseLabel: String

    var body: some View {
        DeviceListExpansionButton(
            isExpanded: $isExpanded,
            expandLabel: expandLabel,
            collapseLabel: collapseLabel
        )
        .allowsHitTesting(false)
        .opacity(0.4)
        .accessibilityHidden(true)
    }
}
