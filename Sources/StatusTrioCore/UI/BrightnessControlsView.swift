import SwiftUI

/// The brightness section of the status panel: one row per connected display.
/// Each row is a single inline capsule whose display name lives inside the bar
/// (no separate title line).
struct BrightnessControlsView: View {
    let state: BrightnessPanelState
    let actions: StatusPanelActions
    let scrollTargets: PopoverScrollTargets
    let onOpenDisplaySettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(state.rows) { row in
                BrightnessRowView(
                    row: row,
                    actions: actions,
                    scrollTargets: scrollTargets,
                    onOpenDisplaySettings: onOpenDisplaySettings
                )
            }
        }
    }
}

private struct BrightnessRowView: View {
    let row: BrightnessRowState
    let actions: StatusPanelActions
    let scrollTargets: PopoverScrollTargets
    let onOpenDisplaySettings: () -> Void

    @EnvironmentObject private var localization: Localization

    /// Local slider draft. Programmatic reads update it only while the user is
    /// not editing, so a late system echo never fights the drag.
    @State private var draft: Double = 0
    @State private var isEditing = false

    private var isAdjustable: Bool { row.canAdjust && row.scalar != nil }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Same leading footprint as the volume row's mute glyph so the
            // sliders of both sections start on the same x.
            PanelActionGlyph(
                systemName: row.symbolName,
                font: .system(size: 15, weight: .medium)
            )
            .frame(width: PanelSummaryActionMetrics.leadingGlyphSlot)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)

            Group {
                if isAdjustable {
                    PanelLevelSlider(
                        value: sliderBinding,
                        label: row.name,
                        isEnabled: true,
                        accessibilityLabel: row.accessibilityLabel,
                        accessibilityValue: row.percentageText,
                        onEditingChanged: { editing in
                            isEditing = editing
                            if editing {
                                actions.beginBrightnessAdjustment(displayID: row.id)
                            } else {
                                actions.finishBrightnessAdjustment(displayID: row.id)
                            }
                        }
                    )
                } else if let unavailable = row.unavailableText {
                    // Not adjustable: keep the capsule as a clear disabled
                    // placeholder (name inside, reason on the trailing side)
                    // instead of a title line plus a slider.
                    unavailableCapsule(reason: unavailable)
                } else {
                    // Adjustable in principle but the value is unreadable.
                    PanelLevelSlider(
                        value: sliderBinding,
                        label: row.name,
                        isEnabled: false,
                        accessibilityLabel: row.accessibilityLabel,
                        accessibilityValue: row.percentageText,
                        onEditingChanged: { _ in }
                    )
                }
            }
            .frame(minHeight: PanelLevelSliderMetrics.controlHeight)
            .background(
                LevelSliderScrollTarget(
                    targets: scrollTargets,
                    target: .brightness(displayID: row.id)
                )
            )

            Text(isAdjustable ? row.percentageText : "—")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 34, alignment: .trailing)
                .accessibilityHidden(true)

            Button(action: onOpenDisplaySettings) {
                PanelActionGlyph(systemName: "gearshape", size: PanelSummaryActionMetrics.actionSlot)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(localization.string(.brightnessActionOpenSettings))
            .accessibilityLabel(localization.string(.brightnessActionOpenSettings))
        }
        .onAppear { if !isEditing { draft = row.scalar ?? 0 } }
        .onChange(of: row.scalar) { newValue in
            if !isEditing, let newValue {
                draft = newValue
            }
        }
        .onDisappear {
            // A row removed mid-gesture must not leave the pointer gesture open.
            if isEditing {
                isEditing = false
                actions.finishBrightnessAdjustment(displayID: row.id)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.accessibilityLabel)
    }

    /// Disabled-looking capsule used when the display cannot be adjusted.
    private func unavailableCapsule(reason: String) -> some View {
        ZStack {
            Capsule()
                .fill(Color.secondary.opacity(0.12))
                .frame(height: PanelLevelSliderMetrics.barHeight)
            HStack(spacing: 8) {
                Text(row.name)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.primary.opacity(0.6))
                Spacer(minLength: 8)
                Text(reason)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, PanelLevelSliderMetrics.labelLeadingInset)
        }
        .frame(height: PanelLevelSliderMetrics.controlHeight)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityValue(reason)
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: { draft },
            set: { newValue in
                draft = newValue
                actions.setBrightness(newValue, forDisplayID: row.id)
            }
        )
    }
}