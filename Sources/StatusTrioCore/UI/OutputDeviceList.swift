import SwiftUI

struct OutputDeviceList: View {
    @EnvironmentObject private var localization: Localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let rows: [PanelAudioDeviceRow]
    let previewRows: [PanelAudioDeviceRow]
    let visibleLimit: Int?
    let expandLabel: String
    let collapseLabel: String
    let previewLanguageCode: String
    let onSelect: (PanelAudioDeviceID) -> Void
    let onSelectListeningMode: (String, BluetoothListeningMode) -> Void

    @State private var isExpanded = false

    var body: some View {
        let visibleRows = OutputDeviceListPresentation.visibleDevices(
            from: rows,
            limit: visibleLimit,
            isExpanded: isExpanded
        )

        if rows.isEmpty && previewRows.isEmpty {
            Label(localization.string(.volumeOutputEmpty), systemImage: "questionmark.circle")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        } else {
            VStack(spacing: 2) {
                deviceRows(visibleRows)
                ForEach(previewRows) { row in
                    deviceRow(row)
                }
                .environmentObject(PreviewLocalization.forCode(previewLanguageCode) ?? localization)

                if OutputDeviceListPresentation.canToggleExpansion(for: rows, limit: visibleLimit) {
                    Button {
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
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
        }
    }

    private func deviceRows(_ rows: [PanelAudioDeviceRow]) -> some View {
        LazyVStack(spacing: 2) {
            ForEach(rows) { row in deviceRow(row) }
        }
    }

    private func deviceRow(_ row: PanelAudioDeviceRow) -> some View {
        OutputDeviceRow(
            state: row,
            onSelect: { onSelect(row.key) },
            onSelectListeningMode: { mode in
                guard let address = row.listeningModeAddress else { return }
                onSelectListeningMode(address, mode)
            }
        )
    }
}
