import SwiftUI

/// Settings for the app icon: which surfaces show it, and how each surface renders it.
struct AppIconSectionView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    var inputSourceController: InputSourceController? = nil
    @Binding var previewIsDark: Bool
    let onShowIconGuide: () -> Void
    /// When non-`nil` the pane shows only that leaf subtopic beneath the App
    /// Icon category; `nil` keeps the original full-pane layout.
    var subtopic: SettingsSubtopic? = nil
    @EnvironmentObject private var localization: Localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsPage(pinnedHeader: {
            // The live menu bar simulation stays at the top of the pane while
            // the option groups below it scroll.
            StatusIconPreviewCard(
                store: store,
                statusStore: statusStore,
                inputSourceController: inputSourceController,
                isDarkBackground: $previewIsDark
            )
        }) {
            if let subtopic {
                appIconSubpage(subtopic)
            } else {
                fullAppIconContent
            }
        }
        // Every app-icon page keeps the live preview, but a leaf switch should
        // still start at the top of the new page.
        .id(subtopic)
    }

    @ViewBuilder
    private var fullAppIconContent: some View {
        iconGuideGroup
        placementGroup
        menuBarGroup
        statusIconGroup
        MiddleIconSettingsGroup(store: store, statusStore: statusStore)
        dockGroup
        AppIconRingView(store: store)
        AppIconBottomIndicatorView(
            store: store,
            statusStore: statusStore,
            previewIsDark: $previewIsDark
        )
    }

    @ViewBuilder
    private func appIconSubpage(_ subtopic: SettingsSubtopic) -> some View {
        switch subtopic {
        case .appIconAppearance:
            // Surface choice, menu-bar size, shared ring stroke, Dock background
            // and the icon guide all describe the icon as a whole.
            iconGuideGroup
            placementGroup
            menuBarGroup
            statusIconGroup
            dockGroup
        case .appIconRing:
            AppIconRingView(store: store)
        case .appIconMiddleIcon:
            MiddleIconSettingsGroup(store: store, statusStore: statusStore,
                                    showsGroupTitle: false)
        case .appIconBottomIndicator:
            AppIconBottomIndicatorView(
                store: store,
                statusStore: statusStore,
                previewIsDark: $previewIsDark
            )
        default:
            fullAppIconContent
        }
    }

    private var iconGuideGroup: some View {
        SettingsGroup {
            SettingsRow(
                "questionmark.circle",
                tint: .indigo,
                title: localization.string(.guideTitle)
            ) {
                Button(action: onShowIconGuide) {
                    Label(
                        localization.string(.guideOpen),
                        systemImage: "macwindow"
                    )
                }
            }
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

    // MARK: - Shared Status Icon Group

    private var statusIconGroup: some View {
        SettingsGroup(localization.string(.settingsStatusIconTitle)) {
            SettingsPictureRow(
                "circle.circle",
                tint: .indigo,
                title: localization.string(.settingsRingStrokeStyle),
                subtitle: localization.string(.settingsRingStrokeStyleDescription),
                selection: $store.ringStrokeStyle,
                options: [RingStrokeStyle.light, .regular, .bold],
                previewSize: SettingsMetrics.appIconPictureOptionPreviewSize,
                caption: { style in
                    switch style {
                    case .light: return localization.string(.settingsRingStrokeStyleLight)
                    case .regular: return localization.string(.settingsRingStrokeStyleRegular)
                    case .bold: return localization.string(.settingsRingStrokeStyleBold)
                    }
                },
                preview: { style in
                    RingStrokeStylePreview(
                        style: style,
                        isDarkBackground: previewIsDark,
                        store: store,
                        statusStore: statusStore
                    )
                }
            )
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
