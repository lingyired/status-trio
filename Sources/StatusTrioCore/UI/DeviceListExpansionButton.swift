import SwiftUI

/// The Expand / Collapse control under a device list that has more rows than
/// its visible limit. Shared by the output and input lists.
struct DeviceListExpansionButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isExpanded: Bool
    let expandLabel: String
    let collapseLabel: String

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                PanelActionGlyph(
                    systemName: "chevron.down",
                    font: .caption.weight(.semibold),
                    size: 16
                )
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                Text(isExpanded ? collapseLabel : expandLabel)
                    .font(.callout)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .foregroundStyle(.secondary)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
