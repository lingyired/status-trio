import Foundation

// Phase-1 compatibility shims for icon option types whose shape changed on
// `main` (#315 battery markers, #275 bluetooth colour, #205 split gap).
// The retained V1 migration/plugin code still speaks the pre-merge vocabulary;
// these extensions translate it onto the merged models so the V1 layer keeps
// compiling while main owns the runtime. Remove once Phases 2–5 migrate the V1
// code to the new vocabulary.

extension BatteryIconOptions {
    /// Legacy "show percentage" semantic, derived from the #315 marker model.
    var showsPercentage: Bool { onBatteryMarker == .percentage }
    /// Which indicator the connected-without-charging state shows (#195).
    /// Derived from the merged marker model: a bolt or plug marker.
    var connectedIndicator: BatteryConnectedIndicator {
        connectedMarker == .bolt ? .bolt : .plug
    }
    /// Legacy "show charging indicator" semantic.
    var showsChargingIndicator: Bool { chargingMarker != .hidden }
    /// Legacy "show percentage while connected" semantic.
    var showsPercentageWhenConnected: Bool { connectedMarker == .percentage }

    /// Legacy initializer including `showsPercentageWhenConnected`, which the
    /// merged type expresses through `connectedMarker` instead.
    init(
        showsPercentage: Bool,
        showsChargingIndicator: Bool,
        showsChargingEffect: Bool,
        showsChargingBoltHeartbeat: Bool,
        usesStatusColors: Bool = true,
        criticalThreshold: Int = 20,
        showsPercentageWhenConnected: Bool,
        fullThreshold: Int = 100,
        textScale: Double = BatteryIconOptions.defaultTextScale,
        ringStrokeScale: Double = 1.0
    ) {
        self.init(
            showsPercentage: showsPercentage,
            showsChargingIndicator: showsChargingIndicator,
            showsChargingEffect: showsChargingEffect,
            showsChargingBoltHeartbeat: showsChargingBoltHeartbeat,
            usesStatusColors: usesStatusColors,
            criticalThreshold: criticalThreshold,
            connectedIndicator: showsPercentageWhenConnected ? .bolt : .plug,
            fullThreshold: fullThreshold,
            textScale: textScale,
            ringStrokeScale: ringStrokeScale
        )
    }
}

extension ConnectionIconOptions {
    /// Legacy field from the pre-merge model; the merged type expresses the
    /// battery-in-connection-slot choice as `centerSource == .batteryPercentage`.
    var showsBatteryPercentageInConnectionSlot: Bool { centerSource == .batteryPercentage }

    /// Legacy initializer with the pre-merge labels.
    init(
        showsWiFiIconForEthernet: Bool = false,
        showsWiFiIconForHotspot: Bool = false,
        showsWiFiIconForTemporaryConnection: Bool = false,
        showsWiFiIconForInternetSharing: Bool = false,
        showsBatteryPercentageInConnectionSlot: Bool,
        centerSource: ConnectionCenterSource = .network,
        prioritizesNetworkErrorsOverInputSource: Bool = true,
        wifiScale: Double = 1.0
    ) {
        self.init(
            showsWiFiIconForEthernet: showsWiFiIconForEthernet,
            showsWiFiIconForHotspot: showsWiFiIconForHotspot,
            showsWiFiIconForTemporaryConnection: showsWiFiIconForTemporaryConnection,
            showsWiFiIconForInternetSharing: showsWiFiIconForInternetSharing,
            centerSource: showsBatteryPercentageInConnectionSlot ? .batteryPercentage : centerSource,
            prioritizesNetworkErrors: prioritizesNetworkErrorsOverInputSource,
            wifiScale: wifiScale
        )
    }
}

extension BluetoothAudioIconOptions {
    /// Legacy field: the merged model expresses the override through
    /// `networkIconSymbolOverride`.
    var replacesNetworkIcon: Bool { networkIconSymbolOverride != nil }
    /// Legacy field removed in the merged model.
    var prioritizesNetworkErrors: Bool { false }

    /// Legacy initializer with the pre-merge labels.
    init(
        replacesNetworkIcon: Bool,
        usesVolumeColor: Bool = false,
        prioritizesNetworkErrors: Bool = false,
        symbolScale: Double = BluetoothAudioIconOptions.defaultSymbolScale,
        networkIconSymbolOverride: String? = nil,
        iconChoice: BluetoothAudioIconChoice = .automatic
    ) {
        self.init(
            iconColor: .default,
            usesVolumeColor: usesVolumeColor,
            symbolScale: symbolScale,
            networkIconSymbolOverride: networkIconSymbolOverride,
            iconChoice: iconChoice
        )
    }
}
