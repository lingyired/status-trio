import SwiftUI

struct AudioSectionView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @Binding var previewIsDark: Bool
    /// When non-`nil` the pane shows only that leaf subtopic beneath the Audio
    /// category; `nil` keeps the original full-pane layout.
    var subtopic: SettingsSubtopic? = nil
    @EnvironmentObject private var localization: Localization

    var body: some View {
        // The lifecycle stays on this concrete, stable container so the device
        // refresh runs once per appearance, not per leaf switch. Audio is a
        // single pane now; device selection lives beside the volume controls.
        VStack(spacing: 0) {
            SettingsPage(pinnedHeader: {
                StatusIconPreviewCard(
                    store: store,
                    statusStore: statusStore,
                    isDarkBackground: $previewIsDark
                )
            }) {
                fullAudioContent
            }
        }
        .onAppear {
            statusStore.refreshAll()
        }
    }

    @ViewBuilder
    private var fullAudioContent: some View {
        panelVisibilityGroup
        volumeFeedbackGroup
        volumeScrollGroup
        displayRulesGroup
        deviceOrderGroup
        inputDeviceOrderGroup
        externalVolumeGroup
    }

    /// Quick show/hide of the audio modules (output volume and input) in the
    /// status panel.
    private var panelVisibilityGroup: some View {
        SettingsGroup(localization.string(.settingsNetworkPanelGroup)) {
            SettingsToggleRow(
                symbol: "speaker.wave.2",
                tint: .cyan,
                title: localization.string(.settingsPanelShowAudio),
                subtitle: localization.string(.settingsPanelShowItemDescription),
                isOn: Binding(
                    get: {
                        store.enabledPopupSections.contains(.volume)
                            || store.enabledPopupSections.contains(.audioInput)
                    },
                    set: { enabled in
                        store.setPopupSection(.volume, enabled: enabled)
                        store.setPopupSection(.audioInput, enabled: enabled)
                    }
                )
            )
        }
    }

    private var volumeFeedbackGroup: some View {
        SettingsGroup(localization.string(.settingsAudioVolumeFeedbackTitle)) {
            SettingsToggleRow(
                symbol: "bell.and.waves.left.and.right.fill",
                tint: .pink,
                title: localization.string(.settingsAudioVolumeFeedback),
                subtitle: localization.string(.settingsAudioVolumeFeedbackDescription),
                isOn: Binding(
                    get: { store.popupVolumeScrollFeedback },
                    set: { store.setPopupVolumeScrollFeedbackOverride($0) }
                )
            )
        }
    }

    private var volumeScrollGroup: some View {
        SettingsGroup(localization.string(.settingsAudioVolumeScrollGroup)) {
            SettingsToggleRow(
                symbol: "arrow.up.arrow.down.circle.fill",
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

            SettingsDivider()

            SettingsToggleRow(
                symbol: "mic.fill",
                tint: .orange,
                title: localization.string(.settingsAudioShowAllInput),
                subtitle: localization.string(.settingsAudioShowAllInputDescription),
                isOn: $store.alwaysShowsAllInputDevices
            )

            if !store.alwaysShowsAllInputDevices {
                SettingsDivider()

                SettingsRow(
                    title: localization.string(.settingsAudioMaximumVisibleInput),
                    subtitle: localization.string(.settingsAudioMaximumVisibleInputDescription),
                    leading: { SettingsIcon(symbol: "number", tint: .teal) },
                    trailing: {
                        HStack(spacing: 10) {
                            Text("\(store.maxVisibleInputDevices)")
                                .font(.system(size: 13, design: .monospaced))
                                .frame(minWidth: 22, alignment: .trailing)

                            Stepper(
                                localization.string(.settingsAudioMaximumVisibleInput),
                                value: $store.maxVisibleInputDevices,
                                in: SettingsStore.inputDeviceLimitRange
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
                            let isHidden = OutputDeviceListPresentation.isHidden(
                                device,
                                in: store.hiddenOutputDeviceUIDs
                            )
                            AudioDeviceOrderRow(
                                name: device.name ?? localization.string(.volumeOutputUnknownDevice),
                                badge: device.isCurrent ? localization.string(.settingsAudioInUse) : nil,
                                isHidden: isHidden,
                                canHide: device.uid != nil,
                                setHidden: { hidden in
                                    guard let uid = device.uid else { return }
                                    store.setOutputDeviceHidden(uid, hidden: hidden)
                                }
                            ) {
                                AudioOutputDeviceIconView(source: AudioPanelMapper.iconSource(for: device))
                                    .foregroundStyle(device.isCurrent ? Color.accentColor : Color.secondary)
                            }
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
                    .frame(height: orderListHeight(for: orderedDevices.count))
                }
            }
        }
    }

    private var inputDeviceOrderGroup: some View {
        SettingsGroup(localization.string(.settingsAudioInputOrderTitle)) {
            SettingsCustomRow(
                "mic",
                tint: .orange,
                title: localization.string(.settingsAudioInputOrderTitle),
                subtitle: localization.string(.settingsAudioInputOrderDescription)
            ) {
                if !store.enabledPopupSections.contains(.audioInput) {
                    Label(
                        localization.string(.settingsAudioInputOrderSectionOff),
                        systemImage: "info.circle"
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                } else if orderedInputDevices.isEmpty {
                    Label(
                        localization.string(.settingsAudioInputOrderEmpty),
                        systemImage: "questionmark.circle"
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                } else {
                    List {
                        ForEach(orderedInputDevices) { device in
                            let isCurrent = device.id == statusStore.liveInput.defaultDeviceID
                            let isHidden = AudioDeviceOrder.isHidden(
                                uid: device.uid,
                                in: store.hiddenInputDeviceUIDs
                            )
                            AudioDeviceOrderRow(
                                name: AudioInputPresentation.displayName(
                                    for: device,
                                    unknownName: localization.string(.audioInputUnknownDevice)
                                ),
                                badge: isCurrent ? localization.string(.audioInputCurrent) : nil,
                                isHidden: isHidden,
                                canHide: device.uid != nil,
                                setHidden: { hidden in
                                    guard let uid = device.uid else { return }
                                    store.setInputDeviceHidden(uid, hidden: hidden)
                                }
                            ) {
                                Image(systemName: isCurrent ? "mic.fill" : "mic")
                                    .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                            }
                        }
                        .onMove { source, destination in
                            store.moveInputDevices(
                                fromOffsets: source,
                                toOffset: destination,
                                in: orderedInputDevices
                            )
                        }
                    }
                    .listStyle(.inset)
                    .frame(height: orderListHeight(for: orderedInputDevices.count))
                }
            }
        }
    }

    private var externalVolumeGroup: some View {
        let state = betterDisplaySettingsState
        return SettingsGroup(
            localization.string(.settingsAudioExternalVolumeTitle),
            footnote: localization.string(.settingsAudioExternalVolumeFootnote)
        ) {
            SettingsRow(
                "speaker.wave.2",
                tint: .cyan,
                title: localization.string(.settingsAudioExternalVolumeCurrentOutput),
                subtitle: localization.string(.settingsAudioExternalVolumeCurrentOutputDescription)
            ) {
                ExternalVolumeTrailingControl {
                    Text(currentOutputDevice?.name ?? localization.string(.volumeOutputUnknownDevice))
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            }

            SettingsDivider()
            SettingsRow(
                "slider.horizontal.3",
                tint: .orange,
                title: localization.string(.settingsAudioExternalVolumeControlMethod),
                subtitle: localization.string(.settingsAudioExternalVolumeControlMethodDescription)
            ) {
                ExternalVolumeTrailingControl {
                    Picker(
                        localization.string(.settingsAudioExternalVolumeControlMethod),
                        selection: backendBinding
                    ) {
                        Text(localization.string(.settingsAudioExternalVolumeExistingBehavior))
                            .tag(ExternalVolumeBackend.directDDC)
                        Text(localization.string(.settingsAudioExternalVolumeBetterDisplay))
                            .tag(ExternalVolumeBackend.betterDisplay)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .settingsMenuPickerWidth()
                    .disabled(!state.canEditConfiguration)
                    .accessibilityIdentifier("audio.betterDisplay.backend")
                }
            }

            if !state.canEditConfiguration {
                SettingsDivider()
                SettingsHintRow(
                    text: localization.string(.settingsAudioExternalVolumeNoStableOutput)
                )
            }

            if state.showsDisplayPicker {
                SettingsDivider()

                SettingsRow(
                    "display",
                    tint: .blue,
                    title: localization.string(.settingsAudioExternalVolumeDisplay),
                    subtitle: localization.string(.settingsAudioExternalVolumeDisplayDescription)
                ) {
                    ExternalVolumeTrailingControl {
                        Picker(
                            localization.string(.settingsAudioExternalVolumeDisplay),
                            selection: displayBinding
                        ) {
                            ForEach(state.pickerOptions) { option in
                                Text(displayOptionLabel(option))
                                    .help(option.uuid ?? "")
                                    .tag(option.uuid)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .settingsMenuPickerWidth()
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(state.selectedDisplayUUID ?? "")
                        .disabled(!state.canSelectDisplay)
                        .accessibilityIdentifier("audio.betterDisplay.display")
                    }
                }
            }

            if state.configuration.backend == .betterDisplay {
                SettingsDivider()
                SettingsRow(
                    state.setupStatus == .ready ? "checkmark.circle.fill" : "display",
                    tint: state.setupStatus == .ready ? .green : .blue,
                    title: localization.string(.settingsAudioExternalVolumeBetterDisplay),
                    subtitle: localization.string(state.setupStatus.localizationKey)
                ) {
                    if state.showsConnectionControls {
                        ExternalVolumeTrailingControl {
                            HStack(spacing: 8) {
                                if state.setupStatus.isBusy {
                                    ProgressView().controlSize(.small)
                                }
                                Button(localization.string(.settingsAudioExternalVolumeRefresh)) {
                                    betterDisplaySettingsActions.refreshDevices()
                                }
                                .controlSize(.small)
                                .disabled(state.setupStatus.isBusy)
                                .accessibilityIdentifier("audio.betterDisplay.refresh")
                            }
                        }
                    }
                }

                if state.showsConnectionControls {
                    SettingsDivider()
                    SettingsHintRow(
                        text: localization.string(.settingsAudioExternalVolumeRequirements)
                    )
                }
            }
        }
    }

    private var betterDisplaySettingsState: BetterDisplayVolumeSettingsState {
        let outputUID = currentOutputDevice?.uid
        let configuration: ExternalVolumeConfiguration
        if let outputUID {
            configuration = store.externalVolumeConfiguration(for: outputUID)
        } else {
            configuration = .default
        }
        return BetterDisplayVolumeSettingsState(
            outputUID: outputUID,
            configuration: configuration,
            devices: statusStore.betterDisplayDevices,
            availability: statusStore.betterDisplayAvailability,
            runtime: statusStore.betterDisplayState,
            usesNativeVolumeControl: statusStore.liveVolume.controlSource == .native
        )
    }

    private var betterDisplaySettingsActions: BetterDisplayVolumeSettingsActions {
        BetterDisplayVolumeSettingsActions(
            state: betterDisplaySettingsState,
            setConfiguration: { configuration, uid in
                store.setExternalVolumeConfiguration(configuration, for: uid)
            },
            refresh: {
                statusStore.refreshBetterDisplayDevices()
            }
        )
    }

    private var backendBinding: Binding<ExternalVolumeBackend> {
        Binding(
            get: { betterDisplaySettingsState.configuration.backend },
            set: { betterDisplaySettingsActions.setBackend($0) }
        )
    }

    private var displayBinding: Binding<String?> {
        Binding(
            get: { betterDisplaySettingsState.selectedDisplayUUID },
            set: { betterDisplaySettingsActions.selectDisplayUUID($0) }
        )
    }

    private func displayOptionLabel(_ option: BetterDisplayDisplayPickerOption) -> String {
        switch option {
        case .unassociated:
            return localization.string(.settingsAudioExternalVolumeUnassociated)
        case .device(let uuid, let name):
            return betterDisplaySettingsState.deviceLabel(uuid: uuid, name: name)
                ?? "\(localization.string(.settingsAudioExternalVolumeUnnamedDisplay)) · \(uuid.prefix(8))"
        case .unavailable(let uuid):
            return "\(localization.string(.settingsAudioExternalVolumeUnavailableDisplay)) · \(uuid.prefix(8))"
        case .saved(let uuid):
            return "\(localization.string(.settingsAudioExternalVolumeSavedDisplay)) · \(uuid.prefix(8))"
        }
    }

    private var orderedDevices: [AudioOutputDevice] {
        store.orderedOutputDevices(statusStore.snapshot.volume.outputDevices)
    }

    private var currentOutputDevice: AudioOutputDevice? {
        statusStore.liveVolume.currentDevice
            ?? statusStore.liveVolume.outputDevices.first(where: \.isCurrent)
    }

    private var orderedInputDevices: [AudioInputDevice] {
        AudioInputPresentation.ordered(
            statusStore.liveInput.devices,
            currentID: statusStore.liveInput.defaultDeviceID,
            order: store.inputDeviceListPreferences.order,
            locale: localization.resolvedLanguage.locale,
            unknownName: localization.string(.audioInputUnknownDevice)
        )
    }

    private func orderListHeight(for count: Int) -> CGFloat {
        min(max(CGFloat(count) * 32 + 12, 48), 180)
    }
}

/// One row of an audio device order list: the show/hide checkbox, icon, name,
/// current-device badge, and drag handle. A hidden row is dimmed, but it keeps
/// its place and stays draggable so ordering never depends on the checkbox.
private struct AudioDeviceOrderRow<Icon: View>: View {
    @EnvironmentObject private var localization: Localization

    let name: String
    let badge: String?
    let isHidden: Bool
    let canHide: Bool
    let setHidden: (Bool) -> Void
    @ViewBuilder let icon: Icon

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Toggle(name, isOn: Binding(
                get: { !isHidden },
                set: { isShown in setHidden(!isShown) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(!canHide)
            .help(localization.string(.settingsAudioShowDevice))

            icon
                .frame(width: 18, height: 18, alignment: .center)
                .opacity(isHidden ? 0.45 : 1)

            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(isHidden ? Color.secondary : Color.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let badge {
                Text(badge)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
            }

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
}

/// Keeps every control in External Display Volume on one trailing edge.
private struct ExternalVolumeTrailingControl<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            content
        }
        .frame(width: 180)
        .layoutPriority(1)
    }
}
