import SwiftUI

struct AudioSectionView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @EnvironmentObject private var localization: Localization

    var body: some View {
        SettingsPage {
            displayRulesGroup
            deviceOrderGroup
        }
        .onAppear {
            statusStore.refreshAll()
        }
    }

    private var displayRulesGroup: some View {
        SettingsGroup(localization.string(.settingsAudioDisplayRules)) {
            SettingsToggleRow(
                symbol: "speaker.wave.3.fill",
                tint: .cyan,
                title: localization.string(.settingsAudioShowAll),
                subtitle: localization.string(.settingsAudioShowAllDescription),
                isOn: $store.alwaysShowsAllOutputDevices
            )

            if !store.alwaysShowsAllOutputDevices {
                SettingsDivider()

                SettingsRow(
                    title: localization.string(.settingsAudioMaximumVisible),
                    subtitle: localization.string(.settingsAudioMaximumVisibleDescription),
                    leading: { SettingsIcon(symbol: "number", tint: .teal) },
                    trailing: {
                        HStack(spacing: 10) {
                            Text("\(store.maxVisibleOutputDevices)")
                                .font(.system(size: 13, design: .monospaced))
                                .frame(minWidth: 22, alignment: .trailing)

                            Stepper(
                                localization.string(.settingsAudioMaximumVisible),
                                value: $store.maxVisibleOutputDevices,
                                in: SettingsStore.outputDeviceLimitRange
                            )
                            .labelsHidden()
                        }
                    }
                )
            }
        }
    }

    private var deviceOrderGroup: some View {
        SettingsGroup(
            localization.string(.settingsAudioOrderTitle),
            footnote: localization.string(.settingsAudioActiveDeviceFootnote)
        ) {
            SettingsCustomRow(
                "slider.horizontal.3",
                tint: .blue,
                title: localization.string(.settingsAudioOrderTitle),
                subtitle: localization.string(.settingsAudioOrderDescription)
            ) {
                if orderedDevices.isEmpty {
                    Label(
                        localization.string(.settingsAudioOrderEmpty),
                        systemImage: "questionmark.circle"
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                } else {
                    List {
                        ForEach(orderedDevices) { device in
                            HStack(spacing: 10) {
                                Image(systemName: device.isCurrent ? "hifispeaker.fill" : "hifispeaker")
                                    .foregroundStyle(device.isCurrent ? Color.accentColor : Color.secondary)
                                    .frame(width: 18)

                                Text(device.name ?? localization.string(.volumeOutputUnknownDevice))
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if device.isCurrent {
                                    Text(localization.string(.settingsAudioInUse))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Color.accentColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                                }

                                Image(systemName: "line.3.horizontal")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .padding(.vertical, 3)
                        }
                        .onMove { source, destination in
                            store.moveOutputDevices(
                                fromOffsets: source,
                                toOffset: destination,
                                in: orderedDevices
                            )
                        }
                    }
                    .listStyle(.inset)
                    .frame(height: orderListHeight)
                }
            }
        }
    }

    private var orderedDevices: [AudioOutputDevice] {
        store.orderedOutputDevices(statusStore.snapshot.volume.outputDevices)
    }

    private var orderListHeight: CGFloat {
        min(max(CGFloat(orderedDevices.count) * 32 + 12, 48), 180)
    }
}
