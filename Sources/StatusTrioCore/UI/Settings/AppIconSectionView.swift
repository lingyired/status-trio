import SwiftUI

/// Settings for the app icon: which surfaces show it, and how each surface renders it.
struct AppIconSectionView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @Binding var previewIsDark: Bool
    let onShowIconGuide: () -> Void
    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsPage {
            // 1. Ultra-Clear Live Menu Bar Preview
            StatusIconPreviewCard(
                store: store,
                statusStore: statusStore,
                isDarkBackground: $previewIsDark
            )

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

            // 2. Where the icon lives
            placementGroup

            // 3. Menu bar surface
            menuBarGroup

            // 4. Dock surface
            dockGroup
        }
    }

    // MARK: - Placement Group

    private var placementGroup: some View {
        SettingsGroup(localization.string(.settingsAppIconPlacement)) {
            SettingsRow(
                "macwindow.on.rectangle",
                tint: .indigo,
                title: localization.string(.settingsAppIconPlacement),
                subtitle: localization.string(.settingsAppIconPlacementDescription)
            ) {
                Picker(
                    localization.string(.settingsAppIconPlacement),
                    selection: $store.appIconPlacement
                ) {
                    Text(localization.string(.settingsAppIconPlacementMenuBar))
                        .tag(AppIconPlacement.menuBar)
                    Text(localization.string(.settingsAppIconPlacementDock))
                        .tag(AppIconPlacement.dock)
                    Text(localization.string(.settingsAppIconPlacementBoth))
                        .tag(AppIconPlacement.both)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
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
            SettingsCustomRow(
                title: localization.string(.settingsDockIconBackground),
                subtitle: localization.string(.settingsDockIconBackgroundDescription)
            ) {
                HStack(spacing: 12) {
                    DockIconPreviewTile(
                        store: store,
                        statusStore: statusStore,
                        size: 44
                    )

                    Picker(
                        localization.string(.settingsDockIconBackground),
                        selection: $store.dockIconBackgroundPreference
                    ) {
                        Text(localization.string(.settingsDockIconBackgroundSystem))
                            .tag(DockIconBackgroundPreference.system)
                        Text(localization.string(.settingsDockIconBackgroundDark))
                            .tag(DockIconBackgroundPreference.dark)
                        Text(localization.string(.settingsDockIconBackgroundLight))
                            .tag(DockIconBackgroundPreference.light)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()

                    Spacer(minLength: 0)
                }
            }
        }
    }
}
