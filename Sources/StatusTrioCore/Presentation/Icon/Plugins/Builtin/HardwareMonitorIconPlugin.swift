import Foundation

struct HardwareMonitorIconPlugin: IconContentPlugin {
    let descriptor = IconContentPluginDescriptor(id: "builtin.hardware-monitor", presentations: [
        .init(id: "ring", slot: .outerRing, title: .hardwareMonitorTitle,
              isSelectable: true, summary: .hardwareMonitorSettingsMetricsDescription),
        // A footer presentation that draws one configured metric as the bottom
        // indicator bar. Not user-selectable from the plugin picker: the bottom
        // indicator's own source menu chooses the metric, and this binding is
        // derived from `bottomIndicatorSource == .metric`.
        .init(id: "footer", slot: .footer, title: .hardwareMonitorTitle,
              isSelectable: false)
    ])

    func resolve(presentationID: String, context: IconContentContext) -> SourceResult<IconContentPayload> {
        if presentationID == "footer" {
            let state = HardwareRingMapper.footerState(
                metric: context.bottomIndicatorMetric,
                snapshot: context.inputs.sources.hardwareMetrics,
                configuration: context.configuration.behaviors.hardwareRing,
                levels: context.inputs.sources.hardwareRingLevels,
                metricColors: context.inputs.sources.hardwareMetricColors,
                speedCapsMbps: context.inputs.sources.hardwareSpeedCapsMbps,
                now: context.now,
                style: context.inputs.system.bottomIndicatorStyle,
                strokeScale: context.legacy.volume.ringStrokeScale
            )
            return .available(.footer(state))
        }
        guard presentationID == "ring" else { return .unavailable(.unavailable) }
        // The source is always selectable: even when every metric is currently
        // unreadable the ring keeps its (greyed) track rather than blanking the
        // whole menu-bar icon. Per-metric availability is handled in the mapper.
        let battery = context.inputs.system.snapshot.battery
        let batteryArcColor = IconPresentationMapper.batteryColorRole(
            battery,
            isHighPowerMode: context.inputs.system.isHighPowerMode,
            options: context.legacy.battery
        ).color
        let state = HardwareRingMapper.resolve(
            snapshot: context.inputs.sources.hardwareMetrics,
            configuration: context.configuration.behaviors.hardwareRing,
            levels: context.inputs.sources.hardwareRingLevels,
            metricColors: context.inputs.sources.hardwareMetricColors,
            speedCapsMbps: context.inputs.sources.hardwareSpeedCapsMbps,
            auxiliarySamples: Self.auxiliarySamples(from: context.inputs.system.snapshot, now: context.now),
            battery: battery,
            batteryOptions: context.legacy.battery,
            batteryArcColor: batteryArcColor,
            now: context.now
        )
        return .available(.outerRing(state))
    }

    func dependencies(presentationID: String, context: IconContentDependencyContext) -> IconContentDependencies {
        if presentationID == "footer" {
            guard let metric = context.bottomIndicatorMetric.hardwareMetric else {
                return .init(samples: [.hardwareMonitor],
                             requiresHardwareMonitor: true,
                             hardwareMetricIDs: [.memoryPressure])
            }
            if metric.usesStatusSnapshot {
                var samples: Set<IconPreviewSampleSource> = []
                switch metric {
                case .volume: samples.insert(.systemVolume)
                case .wifiSignal: samples.insert(.network)
                case .batteryLevel: samples.insert(.macBattery)
                default: break
                }
                return .init(samples: samples)
            }
            return .init(samples: [.hardwareMonitor],
                         requiresHardwareMonitor: true,
                         hardwareMetricIDs: [metric.metricID])
        }
        guard presentationID == "ring" else { return .init() }
        let configuration = context.configuration.behaviors.hardwareRing.normalized()
        // Top-marker-only readings (volume, Wi-Fi signal) ride the general status
        // snapshot, so they add no hardware-metric demand.
        let metricIDs = Set(configuration.referencedMetrics
            .filter { !$0.usesStatusSnapshot }
            .map(\.metricID))
        // Battery readings (top marker or arc) come from the battery snapshot
        // instead of the hardware sampler, so they must demand that sample.
        var samples: Set<IconPreviewSampleSource> = [.hardwareMonitor]
        if configuration.topContent.usesBatteryStatus
            || configuration.referencedMetrics.contains(.batteryLevel) {
            samples.insert(.macBattery)
        }
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

        let battery = snapshot.battery
        let batteryPercent: Double? = battery.isPresent ? Double(battery.percentage) : nil
        samples[.batteryLevel] = HardwareMetricSample(
            value: batteryPercent,
            unit: .percent,
            sampledAt: now,
            source: .powerIO,
            availability: batteryPercent == nil ? .unsupported : .measured
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
