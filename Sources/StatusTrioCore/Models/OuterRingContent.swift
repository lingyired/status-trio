import Foundation

/// What the icon's outer ring shows.
///
/// The ring used to be hard-wired to the system battery. This lets the user pick
/// the AirPods battery instead, with the system battery as the fallback when no
/// AirPods are connected (mirroring the centre slot's network fallback).
enum OuterRingContent: String, CaseIterable, Identifiable, Sendable {
    /// The Mac's own battery level (the historical behaviour).
    case systemBattery
    /// The selected AirPods' left/right battery rings.
    case airPodsBattery
    /// System monitoring: CPU/GPU/memory/temperature/fan arcs. Internally
    /// configured (single/dual arc, top marker, colours, thresholds) rather than
    /// exposed as several top-level sources.
    case hardwareMonitor

    var id: Self { self }
}
