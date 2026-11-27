import AppKit

/// Resolves the colour a menu-bar data-source segment should paint with.
///
/// This is a deliberately minimal copy of `HardwareDetailView.metricColor` so the
/// menu bar can reuse the *same* colour definitions (recommended base + user
/// override + battery status colour) without touching the existing detail view.
/// TODO(p3): converge with HardwareDetailView into one shared resolver.
enum MenuBarMetricColorResolver {
    /// The colour a data-source segment inherits from its metric, or nil when the
    /// metric has no data-source colour and should use the system label colour.
    static func sourceColor(
        for metric: MenuBarMetricID,
        overrides: [HardwareMonitorMetric: IconRGBA],
        batteryLevel: Double?
    ) -> IconRGBA? {
        if metric == .batteryLevel {
            return batteryColor(level: batteryLevel ?? 100)
        }
        guard let hardware = MenuBarMetricRegistry.hardwareMonitorMetric(for: metric) else {
            return nil
        }
        return overrides[hardware] ?? HardwareRingColorConfiguration.recommendedBaseColor(for: hardware)
    }

    /// The colour actually painted for a line: fixed wins, otherwise inherit.
    static func appliedColor(line: LineColor, source: IconRGBA?) -> IconRGBA? {
        switch line {
        case .systemDefault:
            return nil
        case .fixed(let value):
            return IconRGBA(red: value.red, green: value.green, blue: value.blue, alpha: value.alpha)
        case .inheritSource:
            return source
        }
    }

    /// Battery level uses the status colour band (critical/low/normal) so the
    /// value reads as a health signal, matching the icon ring's intent.
    static func batteryColor(level: Double) -> IconRGBA {
        if level <= 10 {
            return IconRGBA(red: 1.0, green: 0.231, blue: 0.188, alpha: 1) // system red
        }
        if level <= 20 {
            return IconRGBA(red: 1.0, green: 0.8, blue: 0.0, alpha: 1) // system yellow
        }
        return HardwareRingColorConfiguration.recommendedBaseColor(for: .batteryLevel)
    }
}
