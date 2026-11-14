import AppKit
import SwiftUI

struct PopoverSectionView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsPage {
            backgroundStyleGroup
            scrollDirectionGroup
            popupOrderGroup
            openBehaviorGroup
        }
    }

    private var scrollDirectionGroup: some View {
        SettingsGroup(
            localization.string(.settingsPopupVolumeScrollGroup),
            footnote: localization.string(.settingsPopupVolumeScrollDirectionDescription)
        ) {
            SettingsToggleRow(
                symbol: "arrow.up.arrow.down",
                tint: .indigo,
                title: localization.string(.settingsPopupVolumeScrollNatural),
                subtitle: localization.string(.settingsPopupVolumeScrollNaturalDescription),
                isOn: $store.popupVolumeNaturalScrolling
            )
            SettingsRow(
                "dial.low", tint: .indigo,
                title: localization.string(.settingsPopupScrollWheelStep),
                subtitle: localization.string(.settingsPopupScrollWheelStepDescription)
            ) {
                HStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { store.popupScrollWheelStepPercent },
                            set: { store.popupScrollWheelStepPercent = ($0 * 2).rounded() / 2 }
                        ),
                        in: SettingsStore.popupScrollWheelStepPercentRange
                    )
                        .frame(width: 130)
                        .controlSize(.small)
                        .accessibilityLabel(localization.string(.settingsPopupScrollWheelStep))
                        .accessibilityValue(wheelStepLabel)
                    Text(wheelStepLabel)
                        .monospacedDigit()
                        .frame(minWidth: 48, alignment: .trailing)
                }
            }
        }
    }

    private var wheelStepLabel: String {
        (store.popupScrollWheelStepPercent / 100).formatted(
            .percent.precision(.fractionLength(0...1)).locale(localization.resolvedLanguage.locale)
        )
    }

    private var openBehaviorGroup: some View {
        SettingsGroup(localization.string(.settingsPanelOpenBehaviorTitle)) {
            SettingsToggleRow(
                symbol: "arrow.uturn.backward",
                tint: .purple,
                title: localization.string(.settingsPanelReturnsToSummaryOnOpen),
                subtitle: localization.string(.settingsPanelReturnsToSummaryOnOpenDescription),
                isOn: $store.returnsToSummaryOnOpen
            )
            SettingsDivider()
            SettingsToggleRow(
                symbol: "macwindow.on.rectangle",
                tint: .purple,
                title: localization.string(.settingsPanelKeepOpenForComparison),
                subtitle: localization.string(.settingsPanelKeepOpenForComparisonDescription),
                isOn: $store.keepsPanelOpenWhenOpeningSettings
            )
        }
    }

    private var backgroundStyleGroup: some View {
        SettingsGroup(
            localization.string(.settingsPanelBackgroundTitle),
            footnote: PanelBackgroundStyle.isLiquidGlassAvailable
                ? nil
                : localization.string(.settingsPanelBackgroundStyleLiquidGlassUnavailable)
        ) {
            SettingsPictureRow(
                "square.on.square",
                tint: .purple,
                title: localization.string(.settingsPanelBackgroundStyle),
                subtitle: localization.string(.settingsPanelBackgroundStyleDescription),
                selection: $store.panelBackgroundStyle,
                options: PanelBackgroundStyle.availableStyles,
                previewSize: CGSize(width: 72, height: 48),
                caption: { style in
                    switch style {
                    case .liquidGlass:
                        return localization.string(.settingsPanelBackgroundStyleLiquidGlass)
                    case .classicMaterial:
                        return localization.string(.settingsPanelBackgroundStyleClassicMaterial)
                    case .solid:
                        return localization.string(.settingsPanelBackgroundStyleSolid)
                    }
                },
                preview: { style in
                    PanelBackgroundStylePreview(style: style)
                }
            )
        }
    }

    private var popupOrderGroup: some View {
        SettingsGroup(
            localization.string(.settingsPopupOrder),
            footnote: localization.string(.settingsPopupOrderDescription)
        ) {
            SettingsCustomRow {
                List {
                    ForEach(store.popupSectionOrder) { section in
                        HStack(alignment: .center, spacing: 8) {
                            Toggle("", isOn: visibilityBinding(for: section))
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                                .accessibilityLabel(localization.string(section.titleKey))

                            popupSectionIcon(section)
                                .foregroundStyle(.secondary)
                                .frame(width: 18, height: 18, alignment: .center)

                            Text(localization.string(section.titleKey))
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            PanelActionGlyph(
                                systemName: "line.3.horizontal",
                                font: .caption,
                                size: 18
                            )
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                        }
                        .padding(.vertical, 3)
                    }
                    .onMove { source, destination in
                        store.movePopupSections(fromOffsets: source, toOffset: destination)
                    }
                }
                .listStyle(.inset)
                .frame(height: popupOrderListHeight)
            }
        }
    }

    private func visibilityBinding(for section: PopupSection) -> Binding<Bool> {
        Binding(
            get: { store.enabledPopupSections.contains(section) },
            set: { enabled in
                let wasEnabled = store.enabledPopupSections.contains(section)
                store.setPopupSection(section, enabled: enabled)

                guard section == .bluetooth, enabled != wasEnabled else { return }
                if enabled {
                    NSApp.activate(ignoringOtherApps: true)
                    statusStore.requestBluetoothAuthorization()
                }
            }
        )
    }

    @ViewBuilder
    private func popupSectionIcon(_ section: PopupSection) -> some View {
        if section == .bluetooth {
            BluetoothIcon(size: 16)
        } else {
            Image(systemName: section.systemImage)
                .font(.system(size: 13))
        }
    }

    private var popupOrderListHeight: CGFloat {
        min(max(CGFloat(store.popupSectionOrder.count) * 32 + 12, 48), 180)
    }
}

/// A miniature status panel used as the background-style preview card. The card
/// shows the actual material for Liquid Glass and the classic popover style,
/// and the system window fill (which tracks light / dark) for Solid.
private struct PanelBackgroundStylePreview: View {
    let style: PanelBackgroundStyle

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            VStack(alignment: .leading, spacing: 4) {
                Capsule()
                    .fill(Color.primary.opacity(0.55))
                    .frame(width: 30, height: 4)
                Capsule()
                    .fill(Color.primary.opacity(0.28))
                    .frame(width: 22, height: 3)
                Capsule()
                    .fill(Color.primary.opacity(0.28))
                    .frame(width: 26, height: 3)
            }
            .padding(9)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .liquidGlass:
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.35), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        case .classicMaterial:
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.regularMaterial)
        case .solid:
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        }
    }
}
