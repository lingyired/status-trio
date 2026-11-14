import SwiftUI

struct AudioPrioritySettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    let input: Bool
    @EnvironmentObject private var localization: Localization

    private var enabled: Bool { store.enabledPopupSections.contains(input ? .audioInput : .volume) }
    private var devices: [AudioPriorityDevice] {
        if input {
            return statusStore.liveInput.devices.map { AudioPriorityDevice(id: $0.id, uid: $0.uid, name: $0.name) }
        }
        return statusStore.liveVolume.outputDevices.map { AudioPriorityDevice(id: $0.id, uid: $0.uid, name: $0.name) }
    }
    private var currentID: UInt32? {
        input ? statusStore.liveInput.defaultDeviceID : statusStore.liveVolume.currentDevice?.id
    }
    private var records: [RememberedAudioDevice] {
        var records = input ? store.rememberedAudioInputs : store.rememberedAudioOutputs
        // The first publication can precede persistent device memory by one UI turn.
        for device in devices {
            if let uid = device.uid, !uid.isEmpty, !records.contains(where: { $0.uid == uid }) {
                records.append(RememberedAudioDevice(uid: uid, name: device.name ?? uid))
            }
        }
        return AudioDeviceOrder.ordered(records, using: input ? store.inputDeviceOrder : store.outputDeviceOrder,
                                       uid: { $0.uid })
    }
    private var hidden: Set<String> { input ? store.hiddenInputDeviceUIDs : store.hiddenOutputDeviceUIDs }
    private var failed: Bool { input ? statusStore.inputPriorityFailed : statusStore.outputPriorityFailed }

    var body: some View {
        SettingsGroup(localization.string(input ? .settingsAudioInputOrderTitle : .settingsAudioOrderTitle),
                      footnote: localization.string(.settingsAudioPriorityDescription)) {
            SettingsToggleRow(
                symbol: input ? "mic" : "speaker.wave.2", tint: input ? .orange : .blue,
                title: localization.string(.settingsAudioPriorityToggle),
                subtitle: localization.string(enabled
                    ? (input ? .settingsAudioPriorityInputManual : .settingsAudioPriorityManual)
                    : .settingsAudioPriorityStopped),
                isOn: Binding(get: { input ? store.automaticallySwitchesInput : store.automaticallySwitchesOutput },
                              set: { if input { store.automaticallySwitchesInput = $0 }
                                     else { store.automaticallySwitchesOutput = $0 } })
            )
            .disabled(!enabled)
            if failed {
                Label(localization.string(.settingsAudioPriorityFailed), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).padding(10)
            }
            if records.isEmpty && devices.isEmpty {
                Text(localization.string(input ? .settingsAudioInputOrderEmpty : .settingsAudioOrderEmpty))
                    .foregroundStyle(.secondary).padding(12)
            } else {
                List {
                    ForEach(records) { record in
                        let live = devices.first { $0.uid == record.uid }
                        let connected = live != nil
                        let current = connected && live?.id == currentID
                        HStack(spacing: 10) {
                            Toggle(record.name, isOn: Binding(
                                get: { !hidden.contains(record.uid) },
                                set: { shown in
                                    if input { store.setInputDeviceHidden(record.uid, hidden: !shown) }
                                    else { store.setOutputDeviceHidden(record.uid, hidden: !shown) }
                                }))
                                .toggleStyle(.checkbox).labelsHidden()
                                .help(localization.string(.settingsAudioShowDevice))
                            deviceIcon(live)
                                .frame(width: 18, height: 18)
                            Text(live?.name ?? record.name).lineLimit(1)
                            Spacer(minLength: 4)
                            if current {
                                Text(localization.string(.settingsAudioInUse)).foregroundStyle(Color.accentColor)
                            } else if !connected {
                                Text(localization.string(.settingsAudioPriorityDisconnected)).foregroundStyle(.secondary)
                            }
                            if !connected {
                                Button { store.forgetAudioDevice(record.uid, input: input) } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help(localization.string(.settingsAudioPriorityForget))
                                .accessibilityLabel(localization.string(.settingsAudioPriorityForget))
                            }
                            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .font(.system(size: 12))
                        .opacity(connected && !hidden.contains(record.uid) ? 1 : 0.55)
                    }
                    .onMove { source, destination in
                        store.moveRememberedAudioDevices(fromOffsets: source, toOffset: destination, in: records, input: input)
                    }
                    ForEach(devices.filter { $0.uid == nil || $0.uid?.isEmpty == true }, id: \.id) { device in
                        Label(device.name ?? localization.string(.volumeOutputUnknownDevice), systemImage: input ? "mic" : "speaker")
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.inset)
                .frame(height: min(max(CGFloat(records.count + devices.filter { $0.uid == nil }.count) * 32 + 12, 48), 180))
            }
        }
    }

    @ViewBuilder private func deviceIcon(_ device: AudioPriorityDevice?) -> some View {
        if !input, let device,
           let output = statusStore.liveVolume.outputDevices.first(where: { $0.id == device.id }) {
            AudioOutputDeviceIconView(source: AudioPanelMapper.iconSource(for: output))
        } else {
            Image(systemName: input ? "mic" : "speaker.wave.2")
        }
    }
}
