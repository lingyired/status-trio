import Foundation

enum IconPresentationMapper {
    static func scene(
        inputs: IconPresentationInputs,
        configuration: IconPresentationConfiguration,
        now: Date = Date()
    ) -> IconSceneState {
        IconSceneState(
            outerRing: batteryState(inputs.snapshot.battery, options: configuration.battery),
            center: centerState(inputs: inputs, configuration: configuration, now: now),
            footer: footerState(inputs.snapshot.volume, options: configuration.volume,
                                bluetoothOptions: configuration.bluetooth),
            statusColors: configuration.battery.usesStatusColors
                ? configuration.battery.batteryStatusColors : .standard
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
            segments: [
                RingSegmentState(
                    progress: StatusMappings.batteryProgress(
                        battery,
                        fullThreshold: options.fullThreshold
                    ),
                    color: color
                )
            ],
            gap: gap,
            accessory: accessory,
            effect: effect,
            strokeScale: options.ringStrokeScale
        )
    }

    private static func centerState(
        inputs: IconPresentationInputs,
        configuration: IconPresentationConfiguration,
        now: Date
    ) -> CenterState? {
        let snapshot = inputs.snapshot
        let battery = snapshot.battery
        let connectionOptions = configuration.connection
        let bluetoothOptions = configuration.bluetooth

        // The user asked the centre slot to carry whole-machine watts. This is
        // the one branch that replaces the network content unconditionally. Its
        // text follows the "Wi-Fi Icon Size" centre-symbol scale so the number
        // grows and shrinks with the network glyph it replaces.
        if connectionOptions.centerSource == .power {
            let textScale = connectionOptions.wifiScale
            if let sample = inputs.systemPower,
               sample.isFresh(at: now),
               sample.watts.isFinite {
                // Integer watts, no unit, laid out for at most three digits.
                // Clamp in Double space so a pathological sample can never trap
                // an Int conversion.
                let watts = Int(min(999, max(0, sample.watts)).rounded())
                return .text(IconTextState(text: "\(watts)", color: .primary, scale: textScale))
            }
            // Never a fake 0 W. A battery Mac may still show its level; a Mac
            // with no battery shows an honest placeholder instead of inventing
            // a percentage it does not have.
            if battery.isPresent {
                return .text(IconTextState(text: "\(battery.percentage)", color: .primary, scale: textScale))
            }
            return .text(IconTextState(text: "--", color: .primary, scale: textScale))
        }

        if connectionOptions.centerSource == .batteryPercentage, battery.isPresent {
            // Every numeric centre mode shares the same size rule: the Wi-Fi
            // Icon Size scale, so switching between percentage and watts does
            // not change the number's size.
            return .text(IconTextState(
                text: "\(battery.percentage)",
                color: .primary,
                scale: connectionOptions.wifiScale
            ))
        }

        // The user asked the centre slot to carry the current input source.
        // Everything below this branch is the shipped `.automatic` decision,
        // which also serves as the fallback whenever no source can be drawn.
        if connectionOptions.centerSource == .inputSource,
           let inputSource = inputs.inputSource,
           !(connectionOptions.prioritizesNetworkErrorsOverInputSource
               && StatusMappings.isNetworkOffline(
                   wifi: snapshot.wifi,
                   connection: snapshot.connection
               )) {
            return inputSourceCenterState(inputSource, scale: connectionOptions.wifiScale)
        }

        if StatusMappings.shouldReplaceNetworkIcon(
            currentDevice: snapshot.volume.currentDevice,
            wifi: snapshot.wifi,
            connection: snapshot.connection,
            options: bluetoothOptions
        ) {
            let source: IconSymbolSource
            if let override = bluetoothOptions.networkIconSymbolOverride {
                // The explicitly picked Bluetooth device always wins over the
                // global audio glyph, including when that device is inactive.
                source = .symbol(name: override, variableValue: nil, fallback: "dot.radiowaves.left.and.right")
            } else if snapshot.volume.currentDevice?.isBluetoothAudio == true,
                      let selectedSymbol = bluetoothOptions.iconChoice.symbolName {
                source = .symbol(name: selectedSymbol, variableValue: nil, fallback: "headphones")
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

    /// The input-source glyph: the source's own icon, then its short label,
    /// then a neutral keyboard symbol. Never returns `nil`, so a selected
    /// source can never blank the centre slot.
    ///
    /// `scale` is the Wi-Fi size the user chose: the input source takes over
    /// the slot the Wi-Fi glyph sits in, so it follows the same control from
    /// the same base — the Wi-Fi symbol's point size and the image's 42-unit
    /// box are calibrated to each other, so both grow together.
    private static func inputSourceCenterState(
        _ source: InputSourceDescriptor,
        scale: Double
    ) -> CenterState {
        if let iconURL = source.iconURL {
            return .symbol(IconSymbolState(
                source: .image(url: iconURL, fallbackSymbol: "keyboard"),
                color: .primary,
                scale: scale
            ))
        }
        if let label = source.shortLabel, !label.isEmpty {
            return .text(IconTextState(text: label, color: .primary, scale: scale))
        }
        return .symbol(IconSymbolState(
            source: .symbol(name: "keyboard", variableValue: nil, fallback: nil),
            color: .primary,
            scale: scale
        ))
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
        // An associated interface must never render as a faded, disabled glyph.
        // A missing reading means "unknown", not "no signal", so it keeps the
        // full foreground tint; only a genuinely weak-but-known reading uses the
        // muted track. Otherwise a transient invalid `rssiValue()` blanks the
        // connected icon (issue #110).
        let color: IconColorRole = (rssi == nil) ? .primary : (bars == 0 ? .inactive : .primary)
        return wifiSymbol(variableValue: variableValue, color: color, scale: scale)
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
