import AppKit
import SwiftUI

struct PopoverSectionView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsPage {
            popupOrderGroup
            volumeScrollGroup
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

    private var volumeScrollGroup: some View {
        SettingsGroup(localization.string(.settingsPopupVolumeScrollGroup)) {
            SettingsToggleRow(
                symbol: "speaker.wave.2.fill",
                tint: .cyan,
                title: localization.string(.settingsPopupVolumeScroll),
                subtitle: localization.string(.settingsPopupVolumeScrollDescription),
                isOn: $store.popupScrollAdjustsVolume
            )

            if store.popupScrollAdjustsVolume {
                SettingsDivider()

                SettingsMenuRow(
                    symbol: "aspectratio",
                    tint: .teal,
                    title: localization.string(.settingsPopupVolumeScrollScope),
                    subtitle: localization.string(.settingsPopupVolumeScrollScopeDescription),
                    selection: $store.popupVolumeScrollScope,
                    options: PopupVolumeScrollScope.allCases,
                    label: scrollScopeLabel
                )

                SettingsDivider()

                SettingsToggleRow(
                    symbol: "arrow.up.arrow.down",
                    tint: .indigo,
                    title: localization.string(.settingsPopupVolumeScrollNatural),
                    subtitle: localization.string(.settingsPopupVolumeScrollNaturalDescription),
                    isOn: $store.popupVolumeNaturalScrolling
                )
            }
        }
    }

    private func scrollScopeLabel(_ scope: PopupVolumeScrollScope) -> String {
        switch scope {
        case .panel:
            localization.string(.settingsPopupVolumeScrollScopePanel)
        case .volumeControl:
            localization.string(.settingsPopupVolumeScrollScopeVolumeControl)
        }
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
