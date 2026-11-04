import SwiftUI

/// The brightness section of the status panel: one row per connected display.
/// Names stay beside the native sliders, and larger setups can reveal the
/// displays beyond the first three in an adjacent submenu.
struct BrightnessControlsView: View {
    let state: BrightnessPanelState
    let actions: StatusPanelActions
    let scrollTargets: PopoverScrollTargets
    let onOpenDisplaySettings: () -> Void

    @EnvironmentObject private var localization: Localization
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            displayRows(state.visibleRows(expanded: false))
            if state.hasHiddenRows {
                CascadingSubmenuButton(
                    title: "\(localization.string(.commonExpand)) (+\(state.rows.count - BrightnessPanelState.collapsedDisplayLimit))",
                    isPresented: $isExpanded
                ) {
                    VStack(spacing: 8) {
                        displayRows(Array(state.rows.dropFirst(BrightnessPanelState.collapsedDisplayLimit)))
                    }
                }
                .accessibilityValue(localization.string(isExpanded ? .commonExpanded : .commonCollapsed))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localization.string(.settingsBrightnessGroupTitle))
        .onChange(of: state.rows.map(\.id)) { _ in isExpanded = false }
        .onDisappear { isExpanded = false }
    }

    private func displayRows(_ rows: [BrightnessRowState]) -> some View {
        ForEach(rows) { row in
            BrightnessRowView(
                row: row,
                displayName: state.displayName(
                    for: row, builtInName: localization.string(.settingsBrightnessBuiltIn)
                ),
                actions: actions,
                scrollTargets: scrollTargets,
                onOpenDisplaySettings: onOpenDisplaySettings
            )
        }
    }
}

private struct BrightnessRowView: View {
    let row: BrightnessRowState
    let displayName: String
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
        HStack(alignment: .center, spacing: 8) {
            PanelActionGlyph(
                systemName: row.symbolName,
                font: .system(size: 15, weight: .medium)
            )
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)

            Text(displayName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 72, alignment: .leading)
                .help(accessibilityName)
                .accessibilityHidden(true)

            Group {
                if row.canAdjust {
                    NativePanelLevelSlider(
                        value: sliderBinding,
                        isEnabled: isAdjustable,
                        accessibilityLabel: accessibilityName,
                        accessibilityValue: isAdjustable ? percentageText : localization.string(.brightnessUnavailable),
                        onEditingChanged: { editing in
                            isEditing = editing
                            if !editing {
                                actions.finishBrightnessAdjustment(displayID: row.id)
                            }
                        }
                    )
                    .frame(minWidth: 100)
                } else if let unavailable = row.unavailableText {
                    Text(unavailable)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(unavailable)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(minHeight: PanelLevelSliderMetrics.controlHeight)
            .background(
                LevelSliderScrollTarget(
                    targets: scrollTargets,
                    target: .brightness(displayID: row.id)
                )
            )

            Text(isAdjustable ? percentageText : "—")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
                .accessibilityHidden(true)

            Button(action: onOpenDisplaySettings) {
                PanelActionGlyph(systemName: "gearshape")
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
            if isEditing {
                actions.finishBrightnessAdjustment(displayID: row.id)
                isEditing = false
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityName)
    }

    private var accessibilityName: String { row.isBuiltin ? row.name : displayName }

    private var percentageText: String {
        isEditing ? BrightnessPanelMapper.percentText(draft) : row.percentageText
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
