/// The only persistence boundary for compiled content. Unknown plugin bindings
/// are not silently coerced into an existing V1 source.
enum IconContentLegacyAdapter {
    static func binding(for source: RingSource) -> IconContentBinding? {
        switch source {
        case .systemBattery: .init(pluginID: "builtin.system-battery", presentationID: "ring")
        case .airPodsBattery: .init(pluginID: "builtin.airpods-battery", presentationID: "ring")
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
        ringSource(for: binding)?.rawValue ?? centerSource(for: binding)?.rawValue ?? footerSource(for: binding)?.rawValue
    }
}
