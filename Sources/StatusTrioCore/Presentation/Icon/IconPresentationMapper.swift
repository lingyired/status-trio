import Foundation

enum IconPresentationMapper {
    static func scene(
        inputs: IconPresentationInputs,
        configuration: IconPresentationConfiguration,
        now: Date = Date()
    ) -> IconSceneState {
        // #253: the "charging status inside the ring" middle-icon mode draws the
        // battery/charging status in the centre. The level percentage lives there
        // while on battery, so the top gap closes to keep that number from being
        // drawn twice. While charging / on power the centre shows the bolt or
        // plug instead, so the top gap stays available and keeps the level
        // percentage visible (see `batteryState`).
        let battery = inputs.snapshot.battery
        let chargingStatusCenter = configuration.connection.centerSource == .chargingStatus
            && battery.isPresent
        let closesRing = chargingStatusCenter
            && !battery.isCharging
            && !battery.isConnectedToPower
        return IconSceneState(
            outerRing: batteryState(
                battery,
                isHighPowerMode: inputs.isHighPowerMode,
                options: configuration.battery,
                closesRing: closesRing,
                chargingStatusCenter: chargingStatusCenter
            ),
            center: centerState(inputs: inputs, configuration: configuration, now: now),
            footer: footerState(inputs.snapshot.volume, options: configuration.volume,
                                bluetoothOptions: configuration.bluetooth),
            statusColors: configuration.battery.usesStatusColors
                ? configuration.battery.batteryStatusColors : .standard
        )
    }

    private static func batteryState(
        _ battery: BatteryStatus,
        isHighPowerMode: Bool,
        options: BatteryIconOptions,
        closesRing: Bool,
        chargingStatusCenter: Bool
    ) -> OuterRingState {
        let role = options.usesStatusColors
            ? StatusMappings.batteryColorRole(
                battery,
                criticalThreshold: options.criticalThreshold,
                isHighPowerMode: isHighPowerMode
            )
            : .foreground
        let color: IconColorRole = switch role {
        case .foreground: .primary
        case .critical: .critical
        case .lowPower: .lowPower
        case .highPower: .highPower
        case .charging: .powered
        }

        let naturalGapContent = StatusMappings.batteryGapContent(battery, options: options)
        // The "inside the ring" mode draws its status in the middle slot. When the
        // centre carries the level percentage (on battery) the top gap closes so
        // the same number is not drawn twice. When the centre carries the bolt or
        // plug instead, the top gap shows the level percentage, so the battery
        // percentage is never lost while charging or connected to power.
        let gapContent: BatteryGapContent
        if closesRing {
            gapContent = naturalGapContent
        } else if chargingStatusCenter {
            gapContent = options.showsPercentage ? .percentage : .empty
        } else {
            gapContent = naturalGapContent
        }
        let gapStyle: RingGapStyle = switch gapContent {
        case .empty: .closed
        case .percentage: .value
        case .bolt, .plug: .indicator
        }
        // The "inside the ring" mode draws its status in the middle slot, so the
        // top gap closes and its own accessory (percentage/bolt/plug) is not
        // drawn — otherwise the same value would appear twice.
        let gap: RingGapStyle = closesRing ? .closed : gapStyle
        let accessory: RingAccessoryState?
        if closesRing {
            accessory = nil
        } else {
            accessory = switch gapContent {
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
            strokeScale: options.ringStrokeScale,
            // `.split` only has meaning while a top gap consumes progress, so a
            // closed ring keeps the historical 0–100% arc.
            gapProgressMode: closesRing || !options.splitGapProgress ? .absorbed : .split
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

        if connectionOptions.prioritizesNetworkErrors,
           StatusMappings.isNetworkOffline(wifi: snapshot.wifi, connection: snapshot.connection) {
            return networkState(snapshot: snapshot, options: connectionOptions)
        }

        // The user asked the centre slot to carry whole-machine watts. Its text
        // follows the "Wi-Fi Icon Size" centre-symbol scale so the number grows
        // and shrinks with the network glyph it replaces. A genuine outage was
        // handled above when the warning toggle is on.
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

        if connectionOptions.centerSource == .chargingStatus {
            // The charging status replaces the middle glyph (#253): the level
            // percentage while on battery, the bolt while charging, and the plug
            // whenever the machine is on power (including charged / held). A Mac
            // with no battery has no status to show, so it falls through to the
            // network glyph instead of inventing one.
            let textScale = connectionOptions.wifiScale
            if battery.isPresent {
                if battery.isCharging, !battery.isCharged {
                    return .symbol(IconSymbolState(
                        source: .primitive(.bolt),
                        color: .primary,
                        scale: textScale
                    ))
                }
                if battery.isConnectedToPower {
                    return .symbol(IconSymbolState(
                        source: .primitive(.plug),
                        color: .primary,
                        scale: textScale
                    ))
                }
                return .text(IconTextState(
                    text: "\(battery.percentage)",
                    color: .primary,
                    scale: textScale
                ))
            }
        }

        if connectionOptions.centerSource == .batteryPercentage {
            // Every numeric centre mode shares the same size rule: the Wi-Fi
            // Icon Size scale, so switching between percentage and watts does
            // not change the number's size. A Mac with no battery reports 100
            // through `BatteryStatus.percentage`, so this slot and the top
            // battery indicator agree on the same value.
            return .text(IconTextState(
                text: "\(battery.percentage)",
                color: .primary,
                scale: connectionOptions.wifiScale
            ))
        }

        // Unavailable selected content falls back directly to the network.
        if connectionOptions.centerSource == .inputSource,
           let inputSource = inputs.inputSource {
            return inputSourceCenterState(inputSource, scale: connectionOptions.wifiScale)
        }

        if connectionOptions.centerSource == .bluetoothDevice,
           StatusMappings.canShowBluetoothIcon(
            currentDevice: snapshot.volume.currentDevice,
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

        return networkState(snapshot: snapshot, options: connectionOptions)
    }

    private static func networkState(snapshot: StatusSnapshot, options connectionOptions: ConnectionIconOptions) -> CenterState {
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
