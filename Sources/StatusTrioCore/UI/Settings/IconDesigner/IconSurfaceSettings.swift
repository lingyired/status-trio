import SwiftUI

/// Surface placement, size, and Dock treatment are global icon settings rather than slot composition.
struct IconSurfaceSettings: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @Binding var previewIsDark: Bool
    @EnvironmentObject private var localization: Localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            placementGroup
            menuBarGroup
            dockGroup
        }
    }

    // MARK: - Placement Group

    private var placementGroup: some View {
        SettingsGroup(localization.string(.settingsAppIconPlacement)) {
            SettingsPictureRow(
                "macwindow.on.rectangle",
                tint: .indigo,
                title: localization.string(.settingsAppIconPlacement),
                subtitle: localization.string(.settingsAppIconPlacementDescription),
                selection: $store.appIconPlacement,
                options: [AppIconPlacement.menuBar, .dock, .both],
                previewSize: SettingsMetrics.appIconPictureOptionPreviewSize,
                caption: { placement in
                    switch placement {
                    case .menuBar: return localization.string(.settingsAppIconPlacementMenuBar)
                    case .dock: return localization.string(.settingsAppIconPlacementDock)
                    case .both: return localization.string(.settingsAppIconPlacementBoth)
                    }
                },
                preview: { placement in
                    AppIconPlacementPreview(placement: placement)
                }
            )

            if !store.appIconPlacement.showsDockIcon {
                SettingsDivider()

                SettingsHintRow(
                    text: localization.string(.settingsAppIconDockExitHint)
                )
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Menu Bar Group

    private var menuBarGroup: some View {
        SettingsGroup(localization.string(.settingsMenuBarTitle)) {
            SettingsRow(
                "menubar.rectangle",
                tint: .indigo,
                title: localization.string(.settingsIconSize),
                subtitle: localization.string(.settingsIconSizeDescription)
            ) {
                HStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { store.iconSize },
                            set: { store.iconSize = $0.rounded() }
                        ),
                        in: SettingsStore.iconSizeRange
                    )
                    .frame(width: 130)
                    .controlSize(.small)
                    .accessibilityLabel(localization.string(.settingsIconSize))
                    .accessibilityValue(
                        localization.format(
                            .settingsIconSizeAccessibilityValue,
                            Int(store.iconSize)
                        )
                    )

                    Text("\(Int(store.iconSize)) pt")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Dock Group

    private var dockGroup: some View {
        SettingsGroup(localization.string(.settingsAppIconDockGroup)) {
            SettingsPictureRow(
                "dock.rectangle",
                tint: .indigo,
                title: localization.string(.settingsDockIconBackground),
                optionSymbol: { $0.settingsSymbol },
                selection: $store.dockIconBackgroundPreference,
                options: [DockIconBackgroundPreference.system, .dark, .light],
                previewSize: SettingsMetrics.appIconPictureOptionPreviewSize,
                caption: { pref in
                    switch pref {
                    case .system: return localization.string(.settingsDockIconBackgroundSystem)
                    case .dark: return localization.string(.settingsDockIconBackgroundDark)
                    case .light: return localization.string(.settingsDockIconBackgroundLight)
                    }
                },
                preview: { pref in
                    DockBackgroundPreview(
                        preference: pref,
                        store: store,
                        statusStore: statusStore
                    )
                }
            )

            SettingsDivider()
            SettingsHintRow(
                text: localization.string(.settingsDockIconBackgroundDescription)
            )
        }
    }
}
