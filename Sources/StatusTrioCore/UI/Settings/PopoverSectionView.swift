import AppKit
import SwiftUI

struct PopoverSectionView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @ObservedObject private var helper: PrivilegedHelperManager = .shared
    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsPage {
            keepAwakeGroup
            backgroundStyleGroup
            scrollDirectionGroup
            popupOrderGroup
            openBehaviorGroup
        }
    }

    /// The keep-awake quick actions: one master switch for whether the section
    /// appears in the status panel, the privileged-helper setup, and the two
    /// pills toggled independently.
    private var keepAwakeGroup: some View {
        let sectionEnabled = store.enabledPopupSections.contains(.quickActions)
        let needsApproval = helper.requiresApproval && !helper.isReady
        return SettingsGroup(localization.string(.settingsPopupOrderQuickActions)) {
            SettingsToggleRow(
                symbol: "moon.zzz",
                tint: .indigo,
                title: localization.string(.settingsKeepAwakeShowInPanel),
                isOn: Binding(
                    get: { store.enabledPopupSections.contains(.quickActions) },
                    set: { store.setPopupSection(.quickActions, enabled: $0) }
                )
            )
            SettingsDivider()
            SettingsToggleRow(
                symbol: "lightbulb.fill",
                tint: .orange,
                title: localization.string(.quickActionsDisplaySleep),
                subtitle: localization.string(.quickActionsDisplaySleepDescription),
                isOn: $store.showsKeepScreenButton
            )
            .disabled(!sectionEnabled)
            SettingsToggleRow(
                symbol: "moon.zzz.fill",
                tint: .blue,
                title: localization.string(.quickActionsLidSleep),
                subtitle: localization.string(.quickActionsLidSleepDescription),
                isOn: $store.showsLidSleepButton
            )
            .disabled(!sectionEnabled)
            SettingsDivider()
            SettingsToggleRow(
                symbol: "lock.shield",
                tint: .green,
                title: localization.string(.settingsKeepAwakeHelper),
                isOn: helper.isEnabledBinding
            )
            .disabled(!helper.isAvailable)
            if helper.isAvailable {
                Button {
                    helper.openLoginItemsSettings()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: needsApproval ? "exclamationmark.triangle.fill" : "info.circle")
                            .foregroundStyle(needsApproval ? Color.orange : Color.secondary)
                        Text(localization.string(
                            needsApproval ? .lowPowerModeRequiresApproval
                            : (helper.isReady ? .lowPowerModeOpenLoginItems : .lowPowerModeApprovalHint)
                        ))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, SettingsMetrics.rowPaddingH)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var scrollDirectionGroup: some View {
        SettingsGroup(
            localization.string(.settingsPopupVolumeScrollDirection),
            footnote: localization.string(.settingsPopupVolumeScrollDirectionDescription)
        ) {
            SettingsToggleRow(
                symbol: "arrow.up.arrow.down",
                tint: .indigo,
                title: localization.string(.settingsPopupVolumeScrollNatural),
                subtitle: localization.string(.settingsPopupVolumeScrollNaturalDescription),
                isOn: $store.popupVolumeNaturalScrolling
            )
        }
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

/// A miniature status panel used as the background-style preview card. It shows
/// the panel background *and* the card surface that goes with it, so the three
/// choices cannot look interchangeable: a translucent wash on Liquid Glass, a
/// material wash on the frosted style, and an opaque system-surface card on
/// Solid. The real window uses `NSGlassEffectView`, which SwiftUI cannot host in
/// a settings swatch, so the glass entry is an honest visual approximation.
private struct PanelBackgroundStylePreview: View {
    let style: PanelBackgroundStyle

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            cardSwatch.padding(7)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
        )
    }

    /// The miniature power card. Its surface follows the panel style the same way
    /// the live cards do, so the preview communicates the card treatment, not just
    /// the window fill.
    private var cardSwatch: some View {
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
        .padding(7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { cardSurface }
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var cardSurface: some View {
        switch style {
        case .liquidGlass:
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.10))
        case .classicMaterial:
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.ultraThinMaterial)
        case .solid:
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
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
