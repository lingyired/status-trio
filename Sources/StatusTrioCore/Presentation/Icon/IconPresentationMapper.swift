import Foundation

enum IconPresentationMapper {
    static func scene(
        inputs: IconPresentationInputs,
        configuration: IconPresentationConfiguration
    ) -> IconSceneState {
        IconSceneState(
            outerRing: batteryState(inputs.snapshot.battery, options: configuration.battery),
            center: centerState(inputs: inputs, configuration: configuration),
            footer: footerState(inputs.snapshot.volume, options: configuration.volume,
                                bluetoothOptions: configuration.bluetooth)
        )
    }

    private static func batteryState(_ battery: BatteryStatus, options: BatteryIconOptions) -> OuterRingState {
        let role = options.usesStatusColors
            ? StatusMappings.batteryColorRole(battery, criticalThreshold: options.criticalThreshold)
            : .foreground
        let color: IconColorRole = switch role {
        case .foreground: .primary
        case .critical: .critical
        case .lowPower: .lowPower
        case .charging: .powered
        }
        let gapContent = StatusMappings.batteryGapContent(battery, options: options)
        let gap: RingGapStyle = switch gapContent {
        case .empty: .closed
        case .percentage: .value
        case .bolt, .plug: .indicator
        }
        let accessory: RingAccessoryState? = switch gapContent {
        case .empty: nil
        case .percentage:
            .text(IconTextState(text: "\(battery.percentage)", color: .primary, scale: options.textScale))
        case .bolt:
            .symbol(IconSymbolState(
                source: .primitive(.bolt),
                color: .primary,
                scale: options.textScale
            ))
        case .plug:
            .symbol(IconSymbolState(
                source: .primitive(.plug),
                color: .primary,
                scale: options.textScale
            ))
        }
        let effect: RingEffectState? = options.showsChargingEffect
                && battery.isPresent
                && battery.isCharging
                && !battery.isCharged
            ? RingEffectState(
                pulsesAccessory: gapContent == .bolt && options.showsChargingBoltHeartbeat,
                tintsAccessory: gapContent == .bolt
                    && options.showsChargingBoltHeartbeat
                    && options.usesStatusColors
                    && role != .foreground
            )
            : nil

        return OuterRingState(
            segments: [RingSegmentState(progress: StatusMappings.batteryProgress(battery), color: color)],
            gap: gap,
            accessory: accessory,
            effect: effect,
            strokeScale: options.ringStrokeScale
        )
    }

    private static func centerState(
        inputs: IconPresentationInputs,
        configuration: IconPresentationConfiguration
    ) -> CenterState? {
        let snapshot = inputs.snapshot
        let battery = snapshot.battery
        let connectionOptions = configuration.connection
        let bluetoothOptions = configuration.bluetooth

        if connectionOptions.showsBatteryPercentageInConnectionSlot, battery.isPresent {
            return .text(IconTextState(text: "\(battery.percentage)", color: .primary, scale: 1))
        }

        if StatusMappings.shouldReplaceNetworkIcon(
            currentDevice: snapshot.volume.currentDevice,
            wifi: snapshot.wifi,
            connection: snapshot.connection,
            options: bluetoothOptions
        ) {
            let source: IconSymbolSource
            if let override = bluetoothOptions.networkIconSymbolOverride {
                source = .symbol(name: override, variableValue: nil, fallback: "dot.radiowaves.left.and.right")
            } else if let audioIcon = inputs.audioIcon {
                source = audioIcon
            } else {
                source = .symbol(name: "headphones", variableValue: nil, fallback: nil)
            }
            return .symbol(IconSymbolState(source: source, color: .bluetooth, scale: bluetoothOptions.symbolScale))
        }

        if snapshot.connection == .ethernet {
            if connectionOptions.showsWiFiIconForEthernet {
                return wifiSymbol(variableValue: 1, color: .primary, scale: connectionOptions.wifiScale)
            }
            return .symbol(IconSymbolState(source: .primitive(.wiredPort), color: .primary, scale: 1))
        }

        return wifiState(snapshot.wifi, options: connectionOptions)
    }

    private static func wifiState(_ wifi: WiFiStatus, options: ConnectionIconOptions) -> CenterState {
        switch wifi.state {
        case .connected:
            return connectedWiFi(rssi: wifi.rssi, scale: options.wifiScale)
        case .notAssociated:
            return wifiSymbol(variableValue: 0, color: .primary, scale: options.wifiScale)
        case .off, .unavailable:
            return wifiSymbol(name: "wifi.slash", variableValue: 1, color: .primary, scale: options.wifiScale)
        case .noInternet:
            return wifiSymbol(name: "wifi.exclamationmark", variableValue: 1, color: .primary, scale: options.wifiScale)
        case .hotspot where options.showsWiFiIconForHotspot:
            return connectedWiFi(rssi: wifi.rssi, scale: options.wifiScale)
        case .hotspot:
            return wifiSymbol(name: "personalhotspot", variableValue: 1, color: .primary, scale: options.wifiScale)
        case .temporary where options.showsWiFiIconForTemporaryConnection:
            return connectedWiFi(rssi: wifi.rssi, scale: options.wifiScale)
        case .temporary:
            return .symbol(IconSymbolState(source: .primitive(.screenWedge), color: .primary, scale: options.wifiScale))
        case .shared where options.showsWiFiIconForInternetSharing:
            return connectedWiFi(rssi: wifi.rssi, scale: options.wifiScale)
        case .shared:
            return .symbol(IconSymbolState(source: .primitive(.arrowWedge), color: .primary, scale: options.wifiScale))
        }
    }

    private static func connectedWiFi(rssi: Int?, scale: Double) -> CenterState {
        let bars = StatusMappings.wifiBars(rssi: rssi)
        let variableValue: Double = switch bars {
        case 3: 1
        case 2: 0.66
        case 1: 0.33
        default: 0
        }
        return wifiSymbol(variableValue: variableValue, color: bars == 0 ? .inactive : .primary, scale: scale)
    }

    private static func wifiSymbol(
        name: String = "wifi",
        variableValue: Double,
        color: IconColorRole,
        scale: Double
    ) -> CenterState {
        .symbol(IconSymbolState(
            source: .symbol(name: name, variableValue: variableValue, fallback: nil),
            color: color,
            scale: scale
        ))
    }

    private static func footerState(
        _ volume: VolumeStatus,
        options: VolumeIconOptions,
        bluetoothOptions: BluetoothAudioIconOptions
    ) -> FooterState {
        let finiteScalar = volume.scalar.flatMap { $0.isFinite ? $0 : nil }
        let mayUseBluetoothColor = bluetoothOptions.usesVolumeColor && volume.currentDevice?.isBluetoothAudio == true

        switch options.displayStyle {
        case .dots:
            let steps = StatusMappings.volumeSteps(scalar: finiteScalar, isMuted: volume.isMuted) ?? 0
            let color: IconColorRole = mayUseBluetoothColor && steps > 0 ? .bluetooth : .primary
            return .dots(DotsState(count: 4, activeCount: steps, color: color,
                                   strokeScale: options.ringStrokeScale))
        case .arc:
            let effectiveProgress = volume.isMuted ? 0 : (finiteScalar ?? 0)
            let color: IconColorRole = mayUseBluetoothColor && effectiveProgress > 0 ? .bluetooth : .primary
            return .arc(ArcState(progress: effectiveProgress, color: color,
                                 strokeScale: options.ringStrokeScale))
        }
    }
}
