import AppKit

/// Representative artwork for the hardware-metric bottom source, used by the
/// settings previews (the source cards and the dot/arc style preview).
///
/// The live icon renders the real metric sample through the hardware-monitor
/// footer plugin; a preview only needs a stable, recognisable bar so the tiles
/// are not blank and every metric has a distinct base colour. The rest of the
/// icon (ring + centre) is drawn from the same fixed sample the other source
/// cards use, so the `metric` card looks like a complete icon rather than a
/// bare bar.
enum BottomIndicatorMetricPreview {
    /// A fixed mid-level fill so every tile reads as "a filled indicator".
    private static let sampleProgress = 0.6

    /// Same fixed sample the sibling source cards draw with.
    private static let snapshot = StatusSnapshot(
        battery: BatteryStatus(
            rawPercentage: 76,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        ),
        wifi: WiFiStatus(state: .connected, rssi: -56),
        connection: .wifi,
        volume: VolumeStatus(
            scalar: 0.6,
            isMuted: false,
            deviceName: "MacBook Speakers"
        )
    )

    static func footerBar(
        metric: HardwareMonitorMetric,
        style: VolumeDisplayStyle,
        strokeScale: Double,
        baseColor: IconRGBA? = nil
    ) -> FooterState {
        let color = IconColorRole.custom(
            baseColor ?? HardwareRingColorConfiguration.recommendedBaseColor(for: metric))
        switch style {
        case .dots:
            return .dots(DotsState(
                count: 4,
                activeCount: StatusMappings.volumeSteps(scalar: sampleProgress, isMuted: false) ?? 2,
                color: color,
                strokeScale: strokeScale))
        case .arc:
            return .arc(ArcState(progress: sampleProgress, color: color, strokeScale: strokeScale))
        }
    }

    /// A full icon scene: the ring and centre come from the shared fixed sample
    /// (rendered via the legacy mapper with a normal source), and only the footer
    /// is swapped for the representative metric bar.
    static func scene(
        metric: HardwareMonitorMetric,
        style: VolumeDisplayStyle,
        strokeScale: Double,
        baseColor: IconRGBA? = nil
    ) -> IconSceneState {
        let configuration = IconPresentationConfiguration(
            battery: .standard,
            connection: .standard,
            volume: VolumeIconOptions(displayStyle: style, ringStrokeScale: strokeScale),
            bluetooth: .standard
        )
        let base = IconPresentationMapper.scene(
            inputs: IconPresentationInputs(
                snapshot: snapshot,
                audioIcon: nil,
                bottomIndicatorSource: .volume
            ),
            configuration: configuration
        )
        return IconSceneState(
            outerRing: base.outerRing,
            center: base.center,
            footer: footerBar(metric: metric, style: style, strokeScale: strokeScale,
                              baseColor: baseColor),
            statusColors: base.statusColors,
            bluetoothIconColor: base.bluetoothIconColor,
            bottomIndicatorSource: .metric
        )
    }
}
