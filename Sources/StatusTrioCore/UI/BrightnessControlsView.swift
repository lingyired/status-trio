import SwiftUI

/// The brightness section of the status panel: one row per connected display.
struct BrightnessControlsView: View {
    let state: BrightnessPanelState
    let actions: StatusPanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(state.rows) { row in
                BrightnessRowView(row: row, actions: actions)
            }
        }
    }
}

private struct BrightnessRowView: View {
    let row: BrightnessRowState
    let actions: StatusPanelActions

    /// Local slider draft. Programmatic reads update it only while the user is
    /// not editing, so a late system echo never fights the drag.
    @State private var draft: Double = 0
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            if row.canAdjust, row.scalar != nil {
                Slider(
                    value: Binding(
                        get: { draft },
                        set: { newValue in
                            draft = newValue
                            actions.setBrightness(newValue, forDisplayID: row.id)
                        }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        isEditing = editing
                        if !editing {
                            actions.finishBrightnessAdjustment(displayID: row.id)
                        }
                    }
                )
                .controlSize(.small)
                .accessibilityLabel(row.accessibilityLabel)
            } else if let unavailable = row.unavailableText {
                Text(unavailable)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .onAppear { if !isEditing { draft = row.scalar ?? 0 } }
        .onChange(of: row.scalar) { newValue in
            if !isEditing, let newValue {
                draft = newValue
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.accessibilityLabel)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: row.symbolName)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(row.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            if row.canAdjust {
                Text(row.percentageText)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}
