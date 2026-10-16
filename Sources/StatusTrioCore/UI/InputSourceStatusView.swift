import SwiftUI

/// The status panel's input-source row.
///
/// The row reports the current source and opens the switching list, the same
/// shape as the battery and network rows: the panel stays a list of rows, and
/// the input sources only appear once the user asks for them.
struct InputSourceStatusView: View {
    @EnvironmentObject private var localization: Localization

    let state: InputSourcePanelState
    let onOpen: () -> Void
    let onOpenKeyboardSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    PanelSymbolView(
                        source: .symbol(name: "keyboard", variableValue: nil, fallback: nil)
                    )
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.title)
                            .font(.headline)
                            .lineLimit(1)
                        subtitle
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.title)
            .accessibilityValue(state.currentName ?? "")

            Button(action: onOpenKeyboardSettings) {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(state.openSettingsLabel)
            .accessibilityLabel(state.openSettingsLabel)
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        if let currentName = state.currentName {
            Text(currentName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(currentName)
        } else {
            Text(verbatim: " ")
                .font(.caption)
                .accessibilityHidden(true)
        }
    }
}
