import Foundation

/// Builds a complete, deterministic resolution input from editor-owned samples.
/// It deliberately has no access to defaults, monitoring, or permission APIs.
enum IconPreviewInputBuilder {
    static func simulated(
        samples: IconPreviewSampleValues,
        configuration: IconConfigurationV1,
        target: IconDesignerBluetoothTarget,
        now: Date,
        runtimeOptions: IconPresentationRuntimeOptions? = nil
    ) -> IconResolutionInputs {
        let batteryPercentage = min(100, max(0, samples.macBattery.percentage))
        let battery = BatteryStatus(
            rawPercentage: samples.macBattery.isPresent ? batteryPercentage : nil,
            isPresent: samples.macBattery.isPresent,
            isCharging: samples.macBattery.isCharging,
            isLowPowerMode: false,
            isConnectedToPower: samples.macBattery.isCharging
        )

        let (wifiState, connection) = networkState(for: samples.network.kind)
        let wifi = WiFiStatus(
            state: wifiState,
            rssi: wifiState.isNetworkAssociated ? samples.network.clampedRSSI : nil,
            nameAccess: .notDetermined
        )
        let networkAvailability: IconSourceAvailability = samples.network.kind == .off
            ? .unavailable(.disconnected)
            : .available

        let volumePercentage = min(100, max(0, samples.systemVolume.percentage))
        let volumeDevice: AudioOutputDevice?
        switch target {
        case .currentAudioOutput where samples.bluetoothTarget.isOnline && samples.bluetoothTarget.isAudio:
            volumeDevice = AudioOutputDevice(
                id: 1,
                name: "Preview audio output",
                isCurrent: true,
                volume: samples.systemVolume.isAvailable ? Double(volumePercentage) / 100 : nil,
                transport: .bluetooth
            )
        default:
            volumeDevice = nil
        }
        let volume = VolumeStatus(
            scalar: samples.systemVolume.isAvailable ? Double(volumePercentage) / 100 : nil,
            isMuted: samples.systemVolume.isMuted,
            deviceName: volumeDevice?.name,
            currentDevice: volumeDevice
        )
        let snapshot = StatusSnapshot(
            battery: battery,
            wifi: wifi,
            connection: connection,
            volume: volume
        )

        // The sample never reads the system input source; it reuses a fixed
        // descriptor so the preview can draw a keyboard layout without TIS.
        let inputSample = samples.inputSource
        let inputSourceDescriptor: InputSourceDescriptor? = inputSample.isAvailable
            ? InputSourceDescriptor(
                id: "com.status-trio.preview.input-source",
                localizedName: inputSample.shortLabel,
                primaryLanguage: nil,
                iconURL: nil,
                shortLabel: inputSample.shortLabel
            )
            : nil

        var availability: [String: IconSourceAvailability] = [
            RingSource.systemBattery.rawValue: samples.macBattery.isPresent
                ? .available
                : .unavailable(.disconnected),
            RingSource.airPodsBattery.rawValue: samples.airPods.leftAvailable || samples.airPods.rightAvailable
                ? .available
                : .unavailable(.unknown),
            CenterSource.network.rawValue: networkAvailability,
            CenterSource.bluetoothAudioOutput.rawValue: samples.bluetoothTarget.isOnline && samples.bluetoothTarget.isAudio
                ? .available
                : .unavailable(.disconnected),
            CenterSource.connectedBluetoothDevice.rawValue: samples.bluetoothTarget.isOnline
                ? .available
                : .unavailable(.disconnected),
            CenterSource.pinnedBluetoothGlyph.rawValue: .available,
            CenterSource.systemBatteryPercentage.rawValue: samples.macBattery.isPresent
                ? .available
                : .unavailable(.disconnected),
            CenterSource.inputSource.rawValue: inputSample.isAvailable
                ? .available
                : .unavailable(.unavailable),
            FooterSource.systemVolume.rawValue: samples.systemVolume.isAvailable
                ? .available
                : .unavailable(.unknown)
        ]

        let connectedSymbol: String?
        let audioIcon: IconSymbolSource?
        switch target {
        case .currentAudioOutput:
            connectedSymbol = nil
            audioIcon = samples.bluetoothTarget.isOnline && samples.bluetoothTarget.isAudio
                ? .symbol(name: samples.bluetoothTarget.symbolName, variableValue: nil, fallback: "headphones")
                : nil
        case .connectedDevice:
            connectedSymbol = samples.bluetoothTarget.isOnline ? samples.bluetoothTarget.symbolName : nil
            audioIcon = nil
        case .preservedUnboundGlyph:
            connectedSymbol = nil
            audioIcon = nil
        }

        if samples.bluetoothTarget.symbolName.isEmpty {
            availability[CenterSource.connectedBluetoothDevice.rawValue] = .unavailable(.unknown)
        }

        return IconResolutionInputs(
            system: IconPresentationInputs(
                snapshot: snapshot,
                audioIcon: audioIcon,
                inputSource: inputSourceDescriptor,
                runtimeOptions: runtimeOptions
            ),
            sources: IconSourceSnapshot(
                availability: availability,
                airPodsBattery: samples.airPods.batterySnapshot(now: now),
                connectedBluetoothDeviceSymbol: connectedSymbol,
                connectedBluetoothDeviceIsAudio: target.isSpecifiedAudioTarget(sample: samples.bluetoothTarget)
            )
        )
    }

    private static func networkState(for kind: IconPreviewNetworkKind) -> (WiFiState, NetworkConnection) {
        switch kind {
        case .wifi: (.connected, .wifi)
        case .noInternet: (.noInternet, .wifi)
        case .off: (.off, .offline)
        case .ethernet: (.off, .ethernet)
        case .hotspot: (.hotspot, .wifi)
        case .temporary: (.temporary, .wifi)
        case .shared: (.shared, .wifi)
        }
    }
}

private extension IconDesignerBluetoothTarget {
    func isSpecifiedAudioTarget(sample: BluetoothTargetPreviewSample) -> Bool? {
        guard case .connectedDevice = self else { return nil }
        return sample.isAudio
    }
}
