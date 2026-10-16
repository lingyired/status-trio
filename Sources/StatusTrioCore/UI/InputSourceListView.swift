import SwiftUI

/// The list the input-source row opens: every enabled, select-capable keyboard
/// input source, with the current one marked and one click away from switching.
struct InputSourceListView: View {
    @EnvironmentObject private var localization: Localization

    let state: InputSourcePanelState
    let onBack: () -> Void
    let onSelect: (String) -> Void
    let onOpenKeyboardSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationBackRow(
                accessibilityLabel: localization.string(.commonBack),
                title: state.title,
                action: onBack
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if let emptyMessage = state.emptyMessage {
                        Text(emptyMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        rows
                    }
                }
            }
            .frame(maxHeight: 330)

            if let failure = state.failureText {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
            }

            Divider()
            Button(state.openSettingsLabel, action: onOpenKeyboardSettings)
                .buttonStyle(.plain)
                .accessibilityLabel(state.openSettingsLabel)
        }
    }

    private var rows: some View {
        VStack(spacing: 2) {
            ForEach(state.rows, id: \.id) { row in
                Button {
                    onSelect(row.id)
                } label: {
                    HStack(spacing: 8) {
                        rowMarker(row)
                            .frame(width: 20, height: 16)
                            .accessibilityHidden(true)

                        Text(row.name)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(row.name)

                        Spacer(minLength: 0)

                        if row.isCurrent {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.name)
                .accessibilityAddTraits(row.isCurrent ? .isSelected : [])
            }
        }
    }

    /// Every row icon is one flat mark in the row's own colour. A source that
    /// ships an icon is reduced to its ink (`InputSourceIconMask`), because a
    /// dark third-party badge would otherwise vanish on the dark panel; a
    /// source without one gets the system input menu's rounded chip with its
    /// letter inside — the shape macOS itself shows for ABC.
    @ViewBuilder
    private func rowMarker(_ row: InputSourcePanelState.Row) -> some View {
        if let iconURL = row.iconURL,
           let image = IconImageDecodeCache.shared.monochromeInputSourceIcon(for: iconURL) {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .foregroundStyle(.primary)
        } else if let marker = row.marker, !marker.isEmpty {
            labelChip(marker)
        } else {
            Image(systemName: "keyboard")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func labelChip(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .blendMode(.destinationOut)
            .frame(width: 18, height: 15)
            .background(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(.primary)
            )
            .compositingGroup()
    }
}
