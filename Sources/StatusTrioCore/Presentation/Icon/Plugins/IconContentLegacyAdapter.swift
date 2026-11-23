/// The only persistence boundary for compiled content. Unknown plugin bindings
/// are not silently coerced into an existing V1 source.
enum IconContentLegacyAdapter {
    static func binding(for source: RingSource) -> IconContentBinding? {
        switch source {
        case .systemBattery: .init(pluginID: "builtin.system-battery", presentationID: "ring")
        case .airPodsBattery: .init(pluginID: "builtin.airpods-battery", presentationID: "ring")
        case .hardwareMonitor: .init(pluginID: "builtin.hardware-monitor", presentationID: "ring")
        case .automaticLegacy: .init(pluginID: "builtin.legacy", presentationID: "ring")
        case .none: nil
        }
    }

    static func binding(for source: CenterSource) -> IconContentBinding? {
        switch source {
        case .systemBatteryPercentage: .init(pluginID: "builtin.system-battery", presentationID: "percentage")
        case .network: .init(pluginID: "builtin.network", presentationID: "center")
        case .inputSource: .init(pluginID: "builtin.input-source", presentationID: "center")
        case .bluetoothAudioOutput: .init(pluginID: "builtin.bluetooth-device", presentationID: "output")
        case .connectedBluetoothDevice: .init(pluginID: "builtin.bluetooth-device", presentationID: "connected")
        case .pinnedBluetoothGlyph: .init(pluginID: "builtin.bluetooth-device", presentationID: "pinned-glyph")
        case .automaticLegacy:
            .init(pluginID: "builtin.legacy", presentationID: "center")
        case .chargingStatus:
            .init(pluginID: "builtin.legacy", presentationID: "charging-status")
        case .power:
            .init(pluginID: "builtin.legacy", presentationID: "power")
        case .none: nil
        }
    }

    static func binding(for source: FooterSource) -> IconContentBinding? {
        switch source {
        case .systemVolume: .init(pluginID: "builtin.system-volume", presentationID: "footer")
        case .none: nil
        }
    }

    /// The bottom indicator's four states map to the same built-in plugin that
    /// already renders that quantity for the other slots. Volume keeps its
    /// dedicated footer presentation; Wi-Fi and battery expose a footer
    /// presentation on their existing plugins.
    static func binding(for source: BottomIndicatorSource) -> IconContentBinding? {
        switch source {
        case .volume: .init(pluginID: "builtin.system-volume", presentationID: "footer")
        case .wifi: .init(pluginID: "builtin.network", presentationID: "footer")
        case .battery: .init(pluginID: "builtin.system-battery", presentationID: "footer")
        case .metric: .init(pluginID: "builtin.hardware-monitor", presentationID: "footer")
        case .hidden: nil
        }
    }

    static func bottomIndicatorSource(for binding: IconContentBinding) -> BottomIndicatorSource? {
        if binding.pluginID == "builtin.hardware-monitor", binding.presentationID == "footer" {
            return .metric
        }
        return BottomIndicatorSource.allCases
            .filter { $0 != .metric }
            .first { Self.binding(for: $0) == binding }
    }

    static func ringSource(for binding: IconContentBinding) -> RingSource? {
        RingSource.allCases.first { Self.binding(for: $0) == binding }
    }

    static func centerSource(for binding: IconContentBinding) -> CenterSource? {
        CenterSource.allCases.first { Self.binding(for: $0) == binding }
    }

    static func footerSource(for binding: IconContentBinding) -> FooterSource? {
        FooterSource.allCases.first { Self.binding(for: $0) == binding }
    }

    static func sourceID(for binding: IconContentBinding) -> String? {
        if let ring = ringSource(for: binding) { return ring.rawValue }
        if let center = centerSource(for: binding) { return center.rawValue }
        if let footer = footerSource(for: binding) { return footer.rawValue }
        if let bottom = bottomIndicatorSource(for: binding) { return bottom.rawValue }
        return nil
    }
}
