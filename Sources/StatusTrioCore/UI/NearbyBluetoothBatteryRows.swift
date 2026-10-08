import SwiftUI

struct NearbyBluetoothBatteryRows: View {
    let rows: [PanelBluetoothDeviceRow]

    static let maximumRowsHeight: CGFloat = 168
    private static let rowSpacing: CGFloat = 2
    private static let rowPitch = BluetoothPanelMetrics.iconColumnWidth + rowSpacing
    private static var rowsThatFit: Int { Int(maximumRowsHeight / rowPitch) }

    var body: some View {
        if rows.count > Self.rowsThatFit {
            ScrollView { content }
                .frame(maxHeight: Self.maximumRowsHeight)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            ForEach(rows, id: \.address) { row in
                HStack(spacing: BluetoothPanelMetrics.iconTextSpacing) {
                    PanelSymbolView(source: row.icon, size: 15)
                        .foregroundStyle(.secondary)
                        .frame(width: BluetoothPanelMetrics.iconColumnWidth, height: BluetoothPanelMetrics.iconColumnWidth)
                        .accessibilityHidden(true)

                    Text(row.title)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 8)

                    Text(row.batteryText ?? "")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.accessibilityLabel)
                .accessibilityValue(row.accessibilityValue)
            }
        }
    }
}
