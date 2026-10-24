import SwiftUI

struct NetworkSectionPresentation: Equatable, Sendable {
    let capabilityPolicy: DistributionCapabilityPolicy

    var showsInternetSharingIconOption: Bool {
        !capabilityPolicy.blocksControl(.internetSharing)
    }
}

/// Settings for how the network indicator is drawn in the status icon.
struct NetworkSectionView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    var inputSourceController: InputSourceController? = nil
    @Binding var previewIsDark: Bool
    var capabilityPolicy: DistributionCapabilityPolicy = .runtimeDefault
    @EnvironmentObject private var localization: Localization

    @State private var showsNetworkIconOptions: Bool = false

    private var presentation: NetworkSectionPresentation {
        NetworkSectionPresentation(capabilityPolicy: capabilityPolicy)
    }

    var body: some View {
        SettingsPage(pinnedHeader: {
            StatusIconPreviewCard(
                store: store,
                statusStore: statusStore,
                inputSourceController: inputSourceController,
                isDarkBackground: $previewIsDark
            )
        }) {
            connectionIconsGroup
            panelGroup
        }
    }

    /// What the network row itself reports, as opposed to how the status icon
    /// draws it. Kept in its own group because the icon options above describe
    /// the menu bar artwork and this decides the panel's second line.
    private var panelGroup: some View {
        SettingsGroup(localization.string(.settingsNetworkPanelGroup)) {
            SettingsToggleRow(
                symbol: "network",
                tint: .cyan,
                title: localization.string(.settingsNetworkShowLocalIP),
                subtitle: localization.string(.settingsNetworkShowLocalIPDescription),
                isOn: $store.showsLocalIPAddress
            )
        }
    }

    private var connectionIconsGroup: some View {
        SettingsGroup(localization.string(.settingsNetworkConnectionIcons)) {
            SettingsMenuRow(
                symbol: "keyboard",
                tint: .indigo,
                title: localization.string(.settingsNetworkCenterSource),
                subtitle: localization.string(.settingsNetworkCenterSourceDescription),
                selection: $store.connectionCenterSource,
                options: ConnectionCenterSource.allCases,
                label: centerSourceLabel
            )

            if store.connectionCenterSource == .inputSource {
                SettingsDivider()

                SettingsToggleRow(
                    symbol: "wifi.exclamationmark",
                    tint: .orange,
                    title: localization.string(.settingsNetworkCenterSourceNetworkWarnings),
                    subtitle: localization.string(.settingsNetworkCenterSourceNetworkWarningsDescription),
                    isOn: $store.prioritizesNetworkErrorsOverInputSource
                )

                SettingsDivider()

                SettingsHintRow(
                    text: localization.string(.settingsNetworkCenterSourceBluetoothFallback)
                )
            }

            SettingsDivider()

            SettingsRow(
                "wifi",
                tint: .blue,
                title: localization.string(.settingsWiFiSymbolScale),
                subtitle: localization.string(.settingsWiFiSymbolScaleDescription)
            ) {
                HStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { store.wifiSymbolScale },
                            set: { store.wifiSymbolScale = (round($0 * 20) / 20) }
                        ),
                        in: SettingsStore.wifiSymbolScaleRange
                    )
                    .frame(width: 130)
                    .controlSize(.small)
                    .accessibilityLabel(localization.string(.settingsWiFiSymbolScale))
                    .accessibilityValue("\(Int(round(store.wifiSymbolScale * 100)))%")

                    Text("\(Int(round(store.wifiSymbolScale * 100)))%")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }

            SettingsDivider()

            SettingsDisclosureRow(
                "cable.connector",
                tint: .teal,
                title: localization.string(.settingsNetworkConnectionIcons),
                subtitle: localization.string(.settingsNetworkConnectionIconsDescription),
                isExpanded: $showsNetworkIconOptions
            )

            if showsNetworkIconOptions {
                VStack(spacing: 0) {
                    SettingsDivider()

                    SettingsToggleRow(
                        symbol: "cable.connector",
                        tint: .teal,
                        title: localization.string(.settingsNetworkWiFiIconForEthernet),
                        isOn: $store.showsWiFiIconForEthernet
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        symbol: "personalhotspot",
                        tint: .blue,
                        title: localization.string(.settingsNetworkWiFiIconForHotspot),
                        isOn: $store.showsWiFiIconForHotspot
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        symbol: "network",
                        tint: .purple,
                        title: localization.string(.settingsNetworkWiFiIconForTemporaryConnection),
                        isOn: $store.showsWiFiIconForTemporaryConnection
                    )

                    if presentation.showsInternetSharingIconOption {
                        SettingsDivider()

                        SettingsToggleRow(
                            symbol: "antenna.radiowaves.left.and.right",
                            tint: .indigo,
                            title: localization.string(.settingsNetworkWiFiIconForInternetSharing),
                            isOn: $store.showsWiFiIconForInternetSharing
                        )
                    }
                }
            }
        }
    }

    private func centerSourceLabel(_ source: ConnectionCenterSource) -> String {
        switch source {
        case .automatic:
            localization.string(.settingsNetworkCenterSourceAutomatic)
        case .inputSource:
            localization.string(.settingsNetworkCenterSourceInputSource)
        }
    }
}
