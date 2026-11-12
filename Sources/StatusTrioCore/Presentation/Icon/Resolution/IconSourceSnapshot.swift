import Foundation

struct IconSourceSnapshot: Equatable, Sendable {
    var availability: [String: IconSourceAvailability]
    var airPodsBattery: AirPodsBatteryIconSnapshot? = nil
    var connectedBluetoothDeviceSymbol: String? = nil
    /// The selected device's capability is separate from the system's current
    /// output device; nil preserves the legacy unknown/default behavior.
    var connectedBluetoothDeviceIsAudio: Bool? = nil
    var holdingSourceIDs: Set<String> = []
    /// The latest hardware-metric samples, read-only for the hardware ring.
    var hardwareMetrics: HardwareMetricsSnapshot = .empty
    /// Debounced warning/critical levels per metric (status colour mode).
    var hardwareRingLevels: [HardwareMonitorMetric: HardwareLoadLevel] = [:]
    /// The shared per-metric base colours (same field as the status-panel bars).
    var hardwareMetricColors: [HardwareMonitorMetric: IconRGBA] = [:]
    /// Broadband caps (Mbps) for the network-speed metrics, so the ring can turn
    /// a throughput sample into a filled fraction.
    var hardwareSpeedCapsMbps: [HardwareMonitorMetric: Double] = [:]

    static let empty = Self(availability: [:])

    func result<Value: Equatable & Sendable>(for sourceID: String, default value: SourceResult<Value>) -> SourceResult<Value> {
        switch availability[sourceID] {
        case .available, nil: value
        case let .unavailable(reason): .unavailable(reason)
        }
    }
}
