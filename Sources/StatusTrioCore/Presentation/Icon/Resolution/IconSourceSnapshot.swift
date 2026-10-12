import Foundation

struct IconSourceSnapshot: Equatable, Sendable {
    var availability: [String: IconSourceAvailability]
    var airPodsBattery: AirPodsBatteryIconSnapshot? = nil
    var connectedBluetoothDeviceSymbol: String? = nil
    /// The selected device's capability is separate from the system's current
    /// output device; nil preserves the legacy unknown/default behavior.
    var connectedBluetoothDeviceIsAudio: Bool? = nil
    var holdingSourceIDs: Set<String> = []

    static let empty = Self(availability: [:])

    func result<Value: Equatable & Sendable>(for sourceID: String, default value: SourceResult<Value>) -> SourceResult<Value> {
        switch availability[sourceID] {
        case .available, nil: value
        case let .unavailable(reason): .unavailable(reason)
        }
    }
}
