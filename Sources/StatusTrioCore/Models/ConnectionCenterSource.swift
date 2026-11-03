import Foundation

/// The exclusive content source for the shared menu bar and Dock centre slot.
enum ConnectionCenterSource: String, CaseIterable, Identifiable, Sendable {
    case network
    case bluetoothDevice
    case inputSource
    case batteryPercentage
    /// Fresh whole-machine watts, or battery level / a neutral placeholder.
    case power

    var id: Self { self }
    var needsPowerSampling: Bool { self == .power }
}
