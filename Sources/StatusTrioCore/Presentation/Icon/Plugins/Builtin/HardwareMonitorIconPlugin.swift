import Foundation

struct HardwareMonitorIconPlugin: IconContentPlugin {
    let descriptor = IconContentPluginDescriptor(id: "builtin.hardware-monitor", presentations: [
        .init(id: "ring", slot: .outerRing, title: .hardwareMonitorTitle,
              isSelectable: true, summary: .hardwareMonitorSettingsMetricsDescription)
    ])

    func resolve(presentationID: String, context: IconContentContext) -> SourceResult<IconContentPayload> {
        guard presentationID == "ring" else { return .unavailable(.unavailable) }
        // The source is always selectable: even when every metric is currently
        // unreadable the ring keeps its (greyed) track rather than blanking the
        // whole menu-bar icon. Per-metric availability is handled in the mapper.
        let state = HardwareRingMapper.resolve(
            snapshot: context.inputs.sources.hardwareMetrics,
            configuration: context.configuration.behaviors.hardwareRing,
            levels: context.inputs.sources.hardwareRingLevels,
            metricColors: context.inputs.sources.hardwareMetricColors,
            speedCapsMbps: context.inputs.sources.hardwareSpeedCapsMbps,
            auxiliarySamples: Self.auxiliarySamples(from: context.inputs.system.snapshot, now: context.now),
            battery: context.inputs.system.snapshot.battery,
            now: context.now
        )
        return .available(.outerRing(state))
    }

    func dependencies(presentationID: String, context: IconContentDependencyContext) -> IconContentDependencies {
        guard presentationID == "ring" else { return .init() }
        let configuration = context.configuration.behaviors.hardwareRing.normalized()
        // Top-marker-only readings (volume, Wi-Fi signal) ride the general status
        // snapshot, so they add no hardware-metric demand.
        let metricIDs = Set(configuration.referencedMetrics
            .filter { !$0.usesStatusSnapshot }
            .map(\.metricID))
        // Battery top markers read the battery snapshot instead of a hardware
        // metric, so the battery sample must be demanded for them to update.
        var samples: Set<IconPreviewSampleSource> = [.hardwareMonitor]
        if configuration.topContent.usesBatteryStatus { samples.insert(.macBattery) }
        return .init(samples: samples, requiresHardwareMonitor: true, hardwareMetricIDs: metricIDs)
    }

    func capabilities(presentationID: String, context: IconContentDependencyContext) -> Set<IconDesignerBehaviorCapability> {
        presentationID == "ring" ? [.hardwareMonitor] : []
    }

    // MARK: - Top-marker-only readings

    /// Turns the general status snapshot into samples for the top-marker-only
    /// metrics. Freshness is "now" because this is rebuilt on every icon tick
    /// (any volume/Wi-Fi change re-triggers icon resolution).
    private static func auxiliarySamples(from snapshot: StatusSnapshot, now: Date) -> [HardwareMonitorMetric: HardwareMetricSample] {
        var samples: [HardwareMonitorMetric: HardwareMetricSample] = [:]

        let volumePercent: Double? = snapshot.volume.scalar.map { scalar in
            min(100, max(0, (scalar * 100).rounded()))
        }
        samples[.volume] = HardwareMetricSample(
            value: volumePercent,
            unit: .percent,
            sampledAt: now,
            source: .mach,
            availability: volumePercent == nil ? .temporarilyUnavailable : .measured,
            sensorLabel: snapshot.volume.deviceName
        )

        let signalPercent: Double? = snapshot.wifi.state.isNetworkAssociated
            ? snapshot.wifi.rssi.map { wifiSignalPercent(rssi: $0) }
            : nil
        samples[.wifiSignal] = HardwareMetricSample(
            value: signalPercent,
            unit: .percent,
            sampledAt: now,
            source: .network,
            availability: signalPercent == nil ? .temporarilyUnavailable : .measured
        )

        return samples
    }

    /// Maps an RSSI (dBm) onto a 0–100% reading: −50 dBm or better is 100%,
    /// −100 dBm or worse is 0%.
    private static func wifiSignalPercent(rssi: Int) -> Double {
        let clamped = min(-50, max(-100, rssi))
        return (Double(clamped) + 100) / 50 * 100
    }
}
