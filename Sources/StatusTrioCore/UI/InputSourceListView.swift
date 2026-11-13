import SwiftUI

/// The list the input-source row opens: every enabled, select-capable keyboard
/// input source, with the current one marked and one click away from switching.
struct InputSourceListView: View {
    @EnvironmentObject private var localization: Localization
    /// The panel owns one outer scroll surface (#237); this page must not add a
    /// second one on top of it.
    @Environment(\.statusPanelManagesScrolling) private var statusPanelManagesScrolling

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

            if statusPanelManagesScrolling {
                sourceRows
            } else {
                ScrollView {
                    sourceRows
                }
                .frame(maxHeight: 330)
            }

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

    private var sourceRows: some View {
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

    private var rows: some View {
        VStack(spacing: 2) {
            ForEach(state.rows, id: \.id) { row in
                Button {
                    onSelect(row.id)
                } label: {
                    HStack(alignment: .center, spacing: 8) {
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
                            PanelActionGlyph(
                                systemName: "checkmark",
                                font: .system(size: 11, weight: .semibold),
                                size: 16
                            )
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
           let image = IconImageDecodeCache.shared.monochromeInputSourceIcon(
               for: iconURL,
               maximumPixelLength: 128
           ) {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .foregroundStyle(.primary)
        } else if let marker = row.marker, !marker.isEmpty {
            InputSourceLabelChip(label: marker)
        } else {
            Image(systemName: "keyboard")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

}

/// The rounded keycap macOS draws for an input source that ships no icon file
/// (the ABC chip), with its letter knocked out so the row shows through.
///
/// The disc is an explicit white in dark mode and black in light mode rather
/// than `.primary`: `.primary` is the label colour, only ~85 % white in dark
/// mode, so a large filled area at that value reads as grey next to the thin,
/// equally bright ink of an icon row. `compositingGroup()` is kept so the
/// destination-out letter erases only the disc and never the row behind it.
struct InputSourceLabelChip: View {
    @Environment(\.statusPanelBoldTextEnabled) private var panelBoldText
    @Environment(\.colorScheme) private var colorScheme

    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: panelBoldText ? .semibold : .regular, design: .rounded))
            .foregroundStyle(.white)
            .blendMode(.destinationOut)
            .frame(width: 18, height: 15)
            .background(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white : Color.black)
            )
            .compositingGroup()
    }
}
