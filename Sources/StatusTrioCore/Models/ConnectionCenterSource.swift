import Foundation

/// The exclusive content source for the shared menu bar and Dock centre slot.
enum ConnectionCenterSource: String, CaseIterable, Identifiable, Sendable {
    case network
    case bluetoothDevice
    case inputSource
    case batteryPercentage
    /// Fresh whole-machine watts, or battery level / a neutral placeholder.
    case power
    /// The battery/charging status drawn inside the ring: the level percentage
    /// while on battery, the bolt while charging, and the plug while connected.
    case chargingStatus

    var id: Self { self }
    var needsPowerSampling: Bool { self == .power }
}
