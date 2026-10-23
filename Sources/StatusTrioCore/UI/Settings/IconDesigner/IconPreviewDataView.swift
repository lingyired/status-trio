import SwiftUI

struct IconPreviewDataView: View {
    @ObservedObject var session: IconDesignerPreviewSession
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    @ObservedObject var localization: Localization

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localization.string(.iconPreviewDataTitle))
                .font(.title2.weight(.semibold))

            Picker(localization.string(.iconPreviewDataMode), selection: Binding(
                get: { session.mode }, set: { session.mode = $0 }
            )) {
                Text(localization.string(.iconPreviewModeLiveShort)).tag(IconPreviewDataMode.live)
                Text(localization.string(.iconPreviewModeSimulatedShort)).tag(IconPreviewDataMode.simulated)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("iconPreviewData.mode")

            VStack(alignment: .leading, spacing: 10) {
                Text(localization.string(session.mode == .simulated ? .iconPreviewDataSimulatedNotice : .iconPreviewDataLiveNotice))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Toggle(localization.string(.iconPreviewDataApplyToRealIcons), isOn: Binding(
                    get: { session.appliesToRealIcons },
                    set: { session.setAppliesToRealIcons($0) }
                ))
                .disabled(!session.canApplyToRealIcons)
                .accessibilityIdentifier("iconPreviewData.applyToRealIcons")

                if session.appliesToRealIcons {
                    Label(localization.string(.iconPreviewDataApplyToRealIconsNotice), systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("iconPreviewData.applyToRealIconsNotice")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))

            if session.mode == .simulated {
                Menu(localization.string(.iconPreviewQuickFill)) {
                    ForEach(IconPreviewQuickFill.allCases, id: \.self) { fill in
                        Button(localization.string(title(for: fill))) {
                            session.applyQuickFill(fill)
                        }
                    }
                }
                .accessibilityIdentifier("iconPreviewData.quickFill")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(orderedUsedSources, id: \.self) { source in
                        sourceGroup(source)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .frame(minWidth: 340, minHeight: 360, alignment: .topLeading)
    }

    private var orderedUsedSources: [IconPreviewSampleSource] {
        [.macBattery, .airPods, .inputSource, .network, .bluetoothTarget, .systemVolume].filter(usedSources.contains)
    }

    private var usedSources: Set<IconPreviewSampleSource> {
        let target = store.connectedBluetoothIconDeviceAddress.map {
            IconDesignerBluetoothTarget.connectedDevice(address: BluetoothBatteryReader.normalizedAddress($0))
        } ?? .currentAudioOutput
        return IconDesignerPreviewSession.usedSources(configuration: store.iconConfiguration, target: target,
                                                       devices: statusStore.bluetoothDevices.devices)
    }

    private func sourceGroup(_ source: IconPreviewSampleSource) -> some View {
        sampleGroup(sourceTitle(source)) {
            if session.mode == .simulated {
                simulatedControls(for: source)
            } else {
                liveStatus(for: source)
            }
        }
        .accessibilityIdentifier("iconPreviewData.source.\(source.accessibilityName)")
    }

    @ViewBuilder
    private func simulatedControls(for source: IconPreviewSampleSource) -> some View {
        switch source {
        case .macBattery:
            Toggle(localization.string(.iconPreviewMacBatteryPresent), isOn: sampleBinding(\.macBattery.isPresent))
            Toggle(localization.string(.iconPreviewScenarioBatteryCharging), isOn: sampleBinding(\.macBattery.isCharging))
                .disabled(!session.samples.macBattery.isPresent)
            percentageSlider(localization.string(.iconPreviewMacBatteryPercentage), value: session.samples.macBattery.percentage) {
                session.setMacBatteryPercentage($0)
            }
            .disabled(!session.samples.macBattery.isPresent)
        case .airPods:
            earEditor(.left)
            earEditor(.right)
            HStack {
                preset(.both, title: localization.string(.iconDesignerAirPodsTestBoth))
                preset(.leftOnly, title: localization.string(.iconDesignerAirPodsTestLeftOnly))
                preset(.rightOnly, title: localization.string(.iconDesignerAirPodsTestRightOnly))
                preset(.unavailable, title: localization.string(.iconDesignerAirPodsTestUnavailable))
            }
        case .network:
            Picker(localization.string(.iconPreviewNetworkConnectionState), selection: Binding(
                get: { session.samples.network.kind },
                set: { kind in session.updateSamples { $0.network.kind = kind } }
            )) {
                ForEach(IconPreviewNetworkKind.allCases, id: \.self) { kind in
                    Text(networkTitle(kind)).tag(kind)
                }
            }
            .accessibilityIdentifier("iconPreviewData.network.connectionState")
            networkSignalControl
                .disabled(session.samples.network.kind == .off || session.samples.network.kind == .ethernet)
        case .bluetoothTarget:
            Toggle(localization.string(.iconPreviewBluetoothTargetOnline), isOn: sampleBinding(\.bluetoothTarget.isOnline))
            Toggle(localization.string(.iconPreviewBluetoothTargetAudio), isOn: sampleBinding(\.bluetoothTarget.isAudio))
            TextField(localization.string(.iconPreviewBluetoothSampleSymbol), text: sampleBinding(\.bluetoothTarget.symbolName))
        case .systemVolume:
            percentageSlider(localization.string(.iconPreviewSystemVolumePercentage), value: session.samples.systemVolume.percentage) {
                session.setSystemVolumePercentage($0)
            }
            .disabled(!session.samples.systemVolume.isAvailable)
            Toggle(localization.string(.iconPreviewScenarioVolumeMuted), isOn: sampleBinding(\.systemVolume.isMuted))
                .disabled(!session.samples.systemVolume.isAvailable)
            Toggle(localization.string(.iconPreviewVolumeAvailable), isOn: sampleBinding(\.systemVolume.isAvailable))
        case .inputSource:
            Toggle(localization.string(.iconPreviewInputSourceAvailable), isOn: sampleBinding(\.inputSource.isAvailable))
            TextField(localization.string(.iconPreviewInputSourceShortLabel), text: sampleBinding(\.inputSource.shortLabel))
        }
    }

    @ViewBuilder
    private func liveStatus(for source: IconPreviewSampleSource) -> some View {
        switch source {
        case .macBattery:
            let battery = statusStore.snapshot.battery
            Text(battery.isPresent ? "\(battery.percentage)% · \(localization.string(battery.isCharging ? .iconPreviewScenarioBatteryCharging : .iconPreviewScenarioBatteryNotCharging))" : localization.string(.batteryDetailsUnavailable))
                .accessibilityIdentifier("iconPreviewData.live.macBattery")
        case .airPods:
            let live = liveInputs.sources
            if let battery = IconPreviewDataLiveStatus.airPodsBattery(from: live) {
                Text(liveAirPodsSummary(battery))
                    .accessibilityIdentifier("iconPreviewData.live.airPods")
            } else {
                Text(localization.string(.bluetoothBatteryUnavailable))
                    .accessibilityIdentifier("iconPreviewData.live.airPodsUnavailable")
            }
        case .network:
            let connection = statusStore.snapshot.connection
            Text(localization.string(connection == .ethernet ? .iconPreviewNetworkEthernetConnected : networkStatusKey(statusStore.snapshot.wifi.state)))
                .accessibilityIdentifier("iconPreviewData.live.network")
            if connection != .ethernet, statusStore.snapshot.wifi.state.isNetworkAssociated {
                HStack {
                    Text(localization.string(.iconPreviewNetworkSignalStrength))
                    Spacer(minLength: 8)
                    Text(statusStore.snapshot.wifi.rssi.map { localization.format(.wifiSummarySignal, $0) }
                         ?? localization.string(.networkDetailUnavailable))
                        .monospacedDigit()
                }
                .accessibilityIdentifier("iconPreviewData.live.networkSignalStrength")
            }
        case .bluetoothTarget:
            Text(liveBluetoothSummary)
                .accessibilityIdentifier("iconPreviewData.live.bluetooth")
        case .systemVolume:
            if let scalar = statusStore.snapshot.volume.scalar {
                Text("\(Int((scalar * 100).rounded()))% · \(statusStore.snapshot.volume.isMuted ? localization.string(.iconPreviewScenarioVolumeMuted) : localization.string(.iconPreviewLiveNotMuted))")
                    .accessibilityIdentifier("iconPreviewData.live.volume")
            } else {
                Text(localization.string(.volumeTitleUnavailable))
                    .accessibilityIdentifier("iconPreviewData.live.volumeUnavailable")
            }
        case .inputSource:
            Text(localization.string(.iconPreviewInputSourceLiveNotice))
                .accessibilityIdentifier("iconPreviewData.live.inputSource")
        }
    }

    private var liveInputs: IconResolutionInputs {
        let snapshot = statusStore.snapshot
        return IconResolutionInputs(
            system: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
            sources: IconPresentationResourceResolver.sourceSnapshot(
                snapshot: snapshot,
                bluetoothDevices: statusStore.bluetoothDevices.devices,
                batteryLevels: statusStore.bluetoothDevices.batteryLevels,
                batteryLevelsUpdatedAt: statusStore.bluetoothDevices.batteryLevelsUpdatedAt,
                selectedAirPodsAddress: store.airPodsIconDeviceAddress,
                selectedConnectedDeviceAddress: store.connectedBluetoothIconDeviceAddress,
                bluetoothAvailability: statusStore.bluetoothDevices.availability
            )
        )
    }

    private var networkSignalControl: some View {
        let title = localization.string(.iconPreviewNetworkSignalStrength)
        let value = localization.format(.wifiSummarySignal, session.samples.network.rssi)
        let range = NetworkPreviewSample.rssiRange
        return VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer(minLength: 8)
                Text(value).monospacedDigit().fixedSize()
            }
            Slider(value: Binding(
                get: { Double(session.samples.network.rssi) },
                set: { session.setNetworkRSSI($0) }
            ), in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
            .accessibilityLabel(title)
            .accessibilityValue(value)
            .accessibilityIdentifier("iconPreviewData.network.signalStrength")
        }
    }

    private var liveBluetoothSummary: String {
        let live = liveInputs.sources
        guard let name = IconPreviewDataLiveStatus.bluetoothDeviceName(
            selectedAddress: store.connectedBluetoothIconDeviceAddress,
            devices: statusStore.bluetoothDevices.devices,
            bluetoothAvailability: statusStore.bluetoothDevices.availability,
            audioOutputAvailability: live.availability[CenterSource.bluetoothAudioOutput.rawValue],
            currentOutput: statusStore.snapshot.volume.currentDevice
        ) else {
            return localization.string(.bluetoothUnavailable)
        }
        return name
    }

    private func liveAirPodsSummary(_ battery: AirPodsBatteryIconSnapshot) -> String {
        [battery.left.map { "L \($0)%" }, battery.right.map { "R \($0)%" }, battery.caseLevel.map { "\($0)%" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func networkStatusKey(_ state: WiFiState) -> LocalizationKey {
        switch state {
        case .connected: .wifiSubtitleConnected
        case .notAssociated: .wifiSubtitleNotAssociated
        case .off: .wifiSubtitleOff
        case .noInternet: .wifiSubtitleNoInternet
        case .hotspot: .wifiSubtitleHotspot
        case .temporary: .wifiSubtitleTemporary
        case .shared: .wifiSubtitleShared
        case .unavailable: .wifiSubtitleUnavailable
        }
    }

    private func title(for fill: IconPreviewQuickFill) -> LocalizationKey {
        switch fill {
        case .networkHealthy: .iconPreviewScenarioNetworkHealthy
        case .networkError: .iconPreviewScenarioNetworkNoInternet
        case .wifiOffEthernetConnected: .iconPreviewScenarioWifiOffEthernet
        case .batteryCharging: .iconPreviewScenarioBatteryCharging
        case .batteryCriticallyLow: .iconPreviewScenarioBatteryLow
        case .volumeMuted: .iconPreviewScenarioVolumeMuted
        case .airPodsConnected: .iconPreviewScenarioAirPodsConnected
        case .airPodsDisconnected: .iconPreviewScenarioAirPodsDisconnected
        }
    }

    private func sourceTitle(_ source: IconPreviewSampleSource) -> String {
        let key: LocalizationKey = switch source {
        case .macBattery: .iconPreviewMacBatterySource
        case .airPods: .iconPreviewAirPodsBatterySource
        case .network: .iconDesignerSourceNetwork
        case .bluetoothTarget: .iconPreviewBluetoothDevicesSource
        case .systemVolume: .iconPreviewSystemVolumeSource
        case .inputSource: .iconDesignerSourceInputSource
        }
        return localization.string(key)
    }

    private func networkTitle(_ kind: IconPreviewNetworkKind) -> String {
        let key: LocalizationKey = switch kind {
        case .wifi: .iconPreviewScenarioNetworkHealthy
        case .noInternet: .iconPreviewScenarioNetworkNoInternet
        case .off: .iconPreviewScenarioWifiOffEthernet
        case .ethernet: .iconPreviewNetworkEthernetConnected
        case .hotspot: .settingsNetworkWiFiIconForHotspot
        case .temporary: .settingsNetworkWiFiIconForTemporaryConnection
        case .shared: .settingsNetworkWiFiIconForInternetSharing
        }
        return localization.string(key)
    }

    private func sampleGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private func sampleBinding<Value>(_ keyPath: WritableKeyPath<IconPreviewSampleValues, Value>) -> Binding<Value> {
        Binding(get: { session.samples[keyPath: keyPath] }, set: { value in
            session.updateSamples { $0[keyPath: keyPath] = value }
        })
    }

    private func percentageSlider(
        _ title: String,
        value: Int,
        set: @escaping @MainActor @Sendable (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading) {
            HStack { Text(title); Spacer(); Text("\(value)%").monospacedDigit() }
            Slider(value: Binding(get: { Double(value) }, set: set), in: 0...100, step: 1)
        }
    }

    private func earEditor(_ ear: IconPreviewEar) -> some View {
        let available = ear == .left ? session.samples.airPods.leftAvailable : session.samples.airPods.rightAvailable
        let percentage = ear == .left ? session.samples.airPods.leftBattery : session.samples.airPods.rightBattery
        let availableKey: LocalizationKey = ear == .left ? .iconDesignerAirPodsTestLeftAvailable : .iconDesignerAirPodsTestRightAvailable
        let batteryKey: LocalizationKey = ear == .left ? .iconDesignerAirPodsTestLeftBattery : .iconDesignerAirPodsTestRightBattery
        return VStack(alignment: .leading) {
            Toggle(localization.string(availableKey), isOn: Binding(
                get: { available }, set: { session.setAirPodsAvailability(ear, isAvailable: $0) }
            ))
            percentageSlider(localization.string(batteryKey), value: percentage) {
                session.setAirPodsBattery(ear, $0)
            }
            .disabled(!available)
        }
    }

    private func preset(_ preset: CustomAirPodsPreviewPreset, title: String) -> some View {
        Button(title) { session.applyAirPodsPreset(preset) }
            .buttonStyle(.bordered)
            .controlSize(.small)
    }
}

private extension IconPreviewSampleSource {
    var accessibilityName: String {
        switch self {
        case .macBattery: "macBattery"
        case .airPods: "airPods"
        case .network: "network"
        case .bluetoothTarget: "bluetooth"
        case .systemVolume: "volume"
        case .inputSource: "inputSource"
        }
    }
}
