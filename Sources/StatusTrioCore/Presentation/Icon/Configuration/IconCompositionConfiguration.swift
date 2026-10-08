import Foundation

enum IconSlot: String, Codable, CaseIterable, Sendable {
    case outerRing
    case center
    case footer
}

enum RingSource: String, Codable, CaseIterable, Sendable {
    case automaticLegacy
    case systemBattery
    case airPodsBattery
    case none
}

enum CenterSource: String, Codable, CaseIterable, Sendable {
    case automaticLegacy
    case network
    case bluetoothAudioOutput
    case pinnedBluetoothGlyph
    case connectedBluetoothDevice
    case systemBatteryPercentage
    case none
}

enum FooterSource: String, Codable, CaseIterable, Sendable {
    case systemVolume
    case none
}

struct SlotSelection<Source: Codable & Hashable & Sendable>: Codable, Equatable, Sendable {
    var primary: Source
    var fallback: Source?

    init(primary: Source, fallback: Source? = nil) {
        self.primary = primary
        self.fallback = fallback
    }
}

struct IconCompositionConfiguration: Codable, Equatable, Sendable {
    var outerRing: SlotSelection<RingSource>
    var center: SlotSelection<CenterSource>
    var footer: SlotSelection<FooterSource>
    var centerOverride: CenterOverridePolicy

    static let classic = Self(
        outerRing: SlotSelection(primary: .automaticLegacy),
        center: SlotSelection(primary: .automaticLegacy),
        footer: SlotSelection(primary: .systemVolume),
        centerOverride: CenterOverridePolicy(networkProblemOverridesPrimary: false)
    )
}

struct CenterOverridePolicy: Codable, Equatable, Sendable {
    var networkProblemOverridesPrimary: Bool
}
