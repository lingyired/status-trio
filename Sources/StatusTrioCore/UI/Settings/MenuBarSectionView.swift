import AppKit
import SwiftUI

struct MenuBarSectionView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @EnvironmentObject private var localization: Localization

    @State private var isDarkPreview: Bool = true
    @State private var showsNetworkIconOptions: Bool = false

    var body: some View {
        SettingsPage {
            // 1. Ultra-Clear Live Menu Bar Preview
            livePreviewStage

            // 2. Icon Sizing
            iconSizeGroup

            // 3. Battery Indicators
            batteryGroup

            // 4. Connection Icons
            connectionIconsGroup
        }
    }

    // MARK: - Ultra-Clear Live Menu Bar Preview

    private var livePreviewStage: some View {
        VStack(spacing: 8) {
            ZStack {
                // Background simulated menu bar glass
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isDarkPreview
                            ? LinearGradient(
                                colors: [
                                    Color(red: 0.16, green: 0.16, blue: 0.19),
                                    Color(red: 0.10, green: 0.10, blue: 0.12)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            : LinearGradient(
                                colors: [
                                    Color(red: 0.96, green: 0.96, blue: 0.98),
                                    Color(red: 0.89, green: 0.89, blue: 0.92)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isDarkPreview
                                    ? Color.white.opacity(0.12)
                                    : Color.black.opacity(0.08),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)

                HStack(spacing: 14) {
                    // Left context
                    HStack(spacing: 6) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 12, weight: .medium))
                        Text(verbatim: "Finder")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(isDarkPreview ? Color.white.opacity(0.75) : Color.black.opacity(0.75))

                    Spacer()

                    // Real-size live icon directly on menu bar (no artificial background box)
                    Image(nsImage: StatusIconRenderer.image(
                        menuBarStatus: MenuBarStatus(snapshot: statusStore.snapshot),
                        size: store.iconSize,
                        options: store.batteryIconOptions,
                        connectionOptions: store.connectionIconOptions,
                        appearance: NSAppearance(named: isDarkPreview ? .darkAqua : .aqua)
                    ))
                    .accessibilityHidden(true)
                    .animation(.easeInOut(duration: 0.15), value: store.iconSize)
                    .animation(.easeInOut(duration: 0.15), value: store.batteryIconOptions)

                    // Clock & Control Center
                    HStack(spacing: 6) {
                        Image(systemName: "switch.2")
                            .font(.system(size: 10))
                        Text(verbatim: "9:41")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(isDarkPreview ? Color.white.opacity(0.65) : Color.black.opacity(0.65))

                    // Theme selector pill
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isDarkPreview.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isDarkPreview ? "moon.fill" : "sun.max.fill")
                                .font(.system(size: 10))
                            Text(localization.string(isDarkPreview ? .settingsPreviewDark : .settingsPreviewLight))
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundStyle(isDarkPreview ? Color.white.opacity(0.85) : Color.black.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(isDarkPreview ? Color.white.opacity(0.15) : Color.black.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                    .help(localization.string(.settingsPreviewToggleHelp))
                }
                .padding(.horizontal, 14)
            }
            .frame(height: 38)

            Text(localization.string(.settingsPreviewHint))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Icon Size Group (Inline Compact Apple Slider)

    private var iconSizeGroup: some View {
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

    // MARK: - Battery Group (Inline Compact Sliders & Switches)

    private var batteryGroup: some View {
        SettingsGroup(localization.string(.settingsBatteryTitle)) {
            // Show Percentage Switch
            SettingsToggleRow(
                symbol: "percent",
                tint: .green,
                title: localization.string(.settingsBatteryShowPercentage),
                isOn: $store.showsBatteryPercentage
            )

            SettingsDivider()

            // Charging Bolt Switch
            SettingsToggleRow(
                symbol: "bolt.fill",
                tint: .yellow,
                title: localization.string(.settingsBatteryShowChargingIndicator),
                subtitle: localization.string(.settingsBatteryChargingDescription),
                isOn: $store.showsChargingIndicator
            )

            // Symbol Scale (Inline compact slider)
            if store.isBatterySymbolSizeEnabled {
                SettingsDivider()

                SettingsRow(
                    "textformat.size",
                    tint: .blue,
                    title: localization.string(.settingsBatterySymbolScale),
                    subtitle: localization.string(.settingsBatterySymbolScaleDescription)
                ) {
                    HStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { store.batterySymbolScale },
                                set: { store.batterySymbolScale = ($0 * 20).rounded() / 20 }
                            ),
                            in: SettingsStore.batterySymbolScaleRange
                        )
                        .frame(width: 130)
                        .controlSize(.small)
                        .accessibilityLabel(
                            localization.string(.settingsBatterySymbolScaleAccessibility)
                        )
                        .accessibilityValue("\(Int(store.batterySymbolScale * 100))%")

                        Text("\(Int(store.batterySymbolScale * 100))%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            SettingsDivider()

            // Status Colors Switch
            SettingsToggleRow(
                symbol: "paintpalette.fill",
                tint: .orange,
                title: localization.string(.settingsBatteryStatusColors),
                subtitle: localization.string(.settingsBatteryStatusColorsDescription),
                isOn: $store.usesBatteryStatusColors
            )

            // Critical Threshold (Inline compact slider)
            if store.usesBatteryStatusColors {
                SettingsDivider()

                SettingsRow(
                    "exclamationmark.triangle.fill",
                    tint: .red,
                    title: localization.string(.settingsBatteryCriticalThreshold),
                    subtitle: localization.string(.settingsBatteryCriticalThresholdDescription)
                ) {
                    HStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { store.batteryCriticalThreshold },
                                set: { store.batteryCriticalThreshold = $0.rounded() }
                            ),
                            in: SettingsStore.batteryCriticalThresholdRange
                        )
                        .frame(width: 130)
                        .controlSize(.small)
                        .accessibilityLabel(
                            localization.string(.settingsBatteryCriticalThreshold)
                        )
                        .accessibilityValue("\(Int(store.batteryCriticalThreshold))%")

                        Text("\(Int(store.batteryCriticalThreshold))%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: - Connection Icons Group

    private var connectionIconsGroup: some View {
        SettingsGroup(
            localization.string(.settingsMenuBarConnectionIcons),
            footnote: localization.string(.settingsMenuBarConnectionIconsDescription)
        ) {
            HStack(alignment: .center, spacing: 12) {
                SettingsIcon(symbol: "cable.connector", tint: .teal)

                VStack(alignment: .leading, spacing: 2) {
                    Text(localization.string(.settingsMenuBarConnectionIcons))
                        .font(.system(size: 13, weight: .regular))
                    Text(localization.string(.settingsMenuBarConnectionIconsDescription))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showsNetworkIconOptions.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showsNetworkIconOptions ? 180 : 0))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, SettingsMetrics.rowPaddingH)
            .padding(.vertical, SettingsMetrics.rowPaddingV)

            if showsNetworkIconOptions {
                VStack(spacing: 0) {
                    SettingsDivider()

                    SettingsToggleRow(
                        symbol: "cable.connector",
                        tint: .teal,
                        title: localization.string(.settingsMenuBarWiFiIconForEthernet),
                        isOn: $store.showsWiFiIconForEthernet
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        symbol: "personalhotspot",
                        tint: .blue,
                        title: localization.string(.settingsMenuBarWiFiIconForHotspot),
                        isOn: $store.showsWiFiIconForHotspot
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        symbol: "network",
                        tint: .purple,
                        title: localization.string(.settingsMenuBarWiFiIconForTemporaryConnection),
                        isOn: $store.showsWiFiIconForTemporaryConnection
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        symbol: "antenna.radiowaves.left.and.right",
                        tint: .indigo,
                        title: localization.string(.settingsMenuBarWiFiIconForInternetSharing),
                        isOn: $store.showsWiFiIconForInternetSharing
                    )
                }
            }
        }
    }
}
