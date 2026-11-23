import Foundation

/// What the bottom indicator under the status icon reports.
///
/// The data source is deliberately separate from `VolumeDisplayStyle`, which
/// only controls how the indicator is *drawn* (four dots or a bottom arc).
/// Every source reuses the same dot/arc artwork; the source decides which
/// quantity fills it. Keeping the two axes apart preserves the stored
/// `volumeDisplayStyle` value and its meaning across upgrades.
public enum BottomIndicatorSource: String, CaseIterable, Identifiable, Codable, Sendable {
    /// The original behaviour: the system output volume.
    case volume
    /// Wi-Fi signal strength, reusing the icon`s existing bar mapping.
    case wifi
    /// The internal battery level.
    case battery
    /// A hardware-monitor metric (CPU/GPU usage, memory, temperature, fan, or
    /// network speed), mirroring the top marker's metric choices. The concrete
    /// metric lives in `SettingsStore.bottomIndicatorMetric`; this case only
    /// says "draw that metric". Kept as its own case (rather than more cases)
    /// because the metric list is defined by `HardwareMonitorMetric` and grows
    /// independently.
    case metric
    /// Draw nothing in the bottom indicator area.
    case hidden

    public var id: String { rawValue }

    /// The source every install falls back to, matching the pre-existing
    /// volume indicator so upgrades keep the same look.
    public static let `default`: BottomIndicatorSource = .volume

    /// Only the volume source feeds the Bluetooth audio colour rule; the
    /// other sources have no audio device to tint against.
    public var supportsBluetoothVolumeColor: Bool {
        self == .volume
    }

    /// Whether the four-dot / arc appearance options apply. Hidden has no
    /// artwork, so its style is irrelevant.
    public var showsStyleOptions: Bool {
        self != .hidden
    }
}
