import SwiftUI

struct OutputDeviceList: View {
    @EnvironmentObject private var localization: Localization
    let rows: [PanelAudioDeviceRow]
    let previewRows: [PanelAudioDeviceRow]
    let visibleLimit: Int?
    let expandLabel: String
    let collapseLabel: String
    let previewLanguageCode: String
    let onSelect: (PanelAudioDeviceID) -> Void
    let onSelectListeningMode: (String, BluetoothListeningMode) -> Void
    /// An equal-height placeholder to draw while the real rows are still being
    /// re-read after the panel reopens. Only used when there are no rows yet.
    var skeleton: PanelListLayoutSnapshot? = nil

    @State private var isExpanded = false

    var body: some View {
        let visibleRows = OutputDeviceListPresentation.visibleDevices(
            from: rows,
            limit: visibleLimit,
            isExpanded: isExpanded
        )

        if let skeleton, rows.isEmpty, previewRows.isEmpty, skeleton.rowCount > 0 {
            VStack(spacing: 2) {
                PanelListSkeleton(
                    rowHeights: skeleton.rowHeights.map { CGFloat($0) },
                    twoLineThreshold: 40
                )
                if skeleton.hasExpansionButton {
                    PanelDeviceListExpansionPlaceholder(
                        expandLabel: expandLabel,
                        collapseLabel: collapseLabel
                    )
                }
            }
        } else if rows.isEmpty && previewRows.isEmpty {
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
                    DeviceListExpansionButton(
                        isExpanded: $isExpanded,
                        expandLabel: expandLabel,
                        collapseLabel: collapseLabel
                    )
                }
            }
        }
    }

    private func deviceRows(_ rows: [PanelAudioDeviceRow]) -> some View {
        // The output device list is small, so a plain stack is cheaper and more
        // stable than a lazy one: a lazy stack may recycle a row that owns an
        // open AirPods disclosure, tearing down its controls model and restarting
        // the async read when the row scrolls back in. A plain stack keeps every
        // row's identity and its local expansion state alive.
        VStack(spacing: 2) {
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
