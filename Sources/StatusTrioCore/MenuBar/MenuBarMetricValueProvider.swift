import Foundation

/// Produces the current display text for each requested metric from existing
/// snapshots. It never samples and never formats through a second code path: the
/// hardware sampler and status store stay the single source of truth.
protocol MenuBarMetricValueProviding {
    func readings(
        for metrics: Set<MenuBarMetricID>,
        hardware: HardwareMetricsSnapshot,
        status: StatusSnapshot
    ) -> [MenuBarMetricID: MenuBarMetricReading]
}

struct MenuBarMetricValueProvider: MenuBarMetricValueProviding {
    /// Resolves a localization key to display text. Defaults to the raw key so
    /// previews/tests stay deterministic; the app injects `Localization`.
    var localize: (LocalizationKey) -> String = { $0.rawValue }
    /// Paths the user ticked for the SSD card's external total. Kept as a
    /// closure so the provider remains a pure read of current settings.
    var externalVolumePaths: () -> Set<String> = { [] }
    /// Live power samples owned by `PowerSamplingService`; the menu-bar
    /// runtime registers its own demand so the panel's rails stay independent.
    var systemPower: () -> SystemPowerSample? = { nil }
    var inputPower: () -> SystemPowerSample? = { nil }
    var batteryPower: () -> BatteryPowerSample? = { nil }

    static let dash = "--"

    func readings(
        for metrics: Set<MenuBarMetricID>,
        hardware: HardwareMetricsSnapshot,
        status: StatusSnapshot
    ) -> [MenuBarMetricID: MenuBarMetricReading] {
        var result: [MenuBarMetricID: MenuBarMetricReading] = [:]
        for metric in metrics {
            result[metric] = reading(for: metric, hardware: hardware, status: status)
        }
        return result
    }

    func reading(
        for metric: MenuBarMetricID,
        hardware: HardwareMetricsSnapshot,
        status: StatusSnapshot
    ) -> MenuBarMetricReading {
        switch metric {
        case .wifiConnectionStatus:
            let connected = status.wifi.state.isNetworkAssociated
            let key: LocalizationKey = connected ? .menuBarMetricWifiConnected : .menuBarMetricWifiDisconnected
            return MenuBarMetricReading(text: localize(key), value: nil, availability: .measured)
        case .batteryLevel:
            guard status.battery.isPresent else {
                return MenuBarMetricReading(text: Self.dash, value: nil, availability: .unsupported)
            }
            let level = Double(status.battery.percentage)
            return MenuBarMetricReading(
                text: MenuBarMetricRegistry.format(level, for: metric),
                value: level,
                availability: .measured
            )
        case .outputVolume:
            guard let scalar = status.volume.scalar else {
                return MenuBarMetricReading(text: Self.dash, value: nil, availability: .collecting)
            }
            let level = min(100, max(0, scalar * 100))
            return MenuBarMetricReading(
                text: MenuBarMetricRegistry.format(level, for: metric),
                value: level,
                availability: .measured
            )
        case .screenBrightness:
            let scalar = status.brightness.displays.first(where: { $0.isBuiltin })?.scalar
                ?? status.brightness.displays.first?.scalar
            guard let scalar else {
                return MenuBarMetricReading(text: Self.dash, value: nil, availability: .collecting)
            }
            let level = min(100, max(0, scalar * 100))
            return MenuBarMetricReading(
                text: MenuBarMetricRegistry.format(level, for: metric),
                value: level,
                availability: .measured
            )
        case .systemPower, .inputPower, .batteryPower:
            let text: String?
            let value: Double?
            if metric == .batteryPower {
                let sample = batteryPower()
                value = sample?.watts
                text = value.map { MenuBarMetricRegistry.format($0, for: metric) }
                guard let sample, sample.isFresh(at: Date()) else {
                    return MenuBarMetricReading(text: Self.dash, value: nil,
                                                availability: .temporarilyUnavailable)
                }
            } else {
                let sample = metric == .systemPower ? systemPower() : inputPower()
                value = sample?.watts
                text = value.map { MenuBarMetricRegistry.format($0, for: metric) }
                guard let sample, sample.isFresh(at: Date()) else {
                    return MenuBarMetricReading(text: Self.dash, value: nil,
                                                availability: .temporarilyUnavailable)
                }
            }
            return MenuBarMetricReading(text: text ?? Self.dash, value: value,
                                        availability: .measured)
        case .diskExternalTotal, .diskExternalFree:
            let selected = externalVolumePaths()
            let volumes = (hardware.diskVolumes ?? []).filter {
                $0.isExternal && selected.contains($0.mountPath)
            }
            guard !volumes.isEmpty else {
                // External volumes are hot-pluggable; an absent volume should
                // make the value disappear rather than reserve a "--" slot.
                return MenuBarMetricReading(text: "", value: nil,
                                            availability: .temporarilyUnavailable)
            }
            let bytes = volumes.reduce(UInt64(0)) { result, volume in
                result + (metric == .diskExternalTotal ? volume.totalBytes : volume.freeBytes)
            }
            let value = Double(bytes)
            return MenuBarMetricReading(
                text: MenuBarMetricRegistry.format(value, for: metric),
                value: value,
                availability: .measured
            )
        case .diskUsagePercent:
            guard let internalCapacity = internalDiskCapacity(in: hardware) else {
                return MenuBarMetricReading(text: Self.dash, value: nil,
                                            availability: .collecting)
            }
            let value = Self.percent(used: internalCapacity.used,
                                     total: internalCapacity.used + internalCapacity.free)
            return Self.derivedReading(value, for: metric)
        case .diskExternalUsagePercent:
            guard !externalVolumePaths().isEmpty,
                  let external = selectedExternalDiskCapacity(in: hardware) else {
                return MenuBarMetricReading(text: "", value: nil,
                                            availability: .temporarilyUnavailable)
            }
            let value = Self.percent(used: external.total - external.free,
                                     total: external.total)
            return Self.derivedReading(value, for: metric)
        case .diskCombinedUsagePercent, .diskCombinedFree:
            guard let internalCapacity = internalDiskCapacity(in: hardware) else {
                return MenuBarMetricReading(text: Self.dash, value: nil,
                                            availability: .collecting)
            }
            let selected = externalVolumePaths()
            guard !selected.isEmpty,
                  let external = selectedExternalDiskCapacity(in: hardware) else {
                return MenuBarMetricReading(text: "", value: nil,
                                            availability: .temporarilyUnavailable)
            }
            let externalTotal = external.total
            let externalFree = external.free
            if metric == .diskCombinedFree {
                let value = internalCapacity.free + externalFree
                return MenuBarMetricReading(
                    text: MenuBarMetricRegistry.format(value, for: metric),
                    value: value,
                    availability: .measured
                )
            }
            let used = internalCapacity.used + (externalTotal - externalFree)
            let total = internalCapacity.used + internalCapacity.free + externalTotal
            return Self.derivedReading(Self.percent(used: used, total: total), for: metric)
        default:
            guard let hardwareID = MenuBarMetricRegistry.hardwareMetricID(for: metric) else {
                return MenuBarMetricReading(text: Self.dash, value: nil, availability: .collecting)
            }
            let sample = hardware.samples[hardwareID]
            let availability = sample?.availability ?? .collecting
            guard availability == .measured, let value = sample?.value else {
                return MenuBarMetricReading(text: Self.dash, value: nil, availability: availability)
            }
            return MenuBarMetricReading(
                text: MenuBarMetricRegistry.format(value, for: metric),
                value: value,
                availability: .measured
            )
        }
    }
    private func internalDiskCapacity(
        in hardware: HardwareMetricsSnapshot
    ) -> (used: Double, free: Double)? {
        guard let used = hardware.samples[.diskUsedBytes],
              used.availability == .measured,
              let usedValue = used.value,
              let free = hardware.samples[.diskFreeBytes],
              free.availability == .measured,
              let freeValue = free.value,
              usedValue >= 0, freeValue >= 0 else { return nil }
        return (usedValue, freeValue)
    }

    private func selectedExternalDiskCapacity(
        in hardware: HardwareMetricsSnapshot
    ) -> (total: Double, free: Double)? {
        let selected = externalVolumePaths()
        let volumes = (hardware.diskVolumes ?? []).filter {
            $0.isExternal && selected.contains($0.mountPath)
        }
        guard !volumes.isEmpty else { return nil }
        let total = volumes.reduce(UInt64(0)) { $0 + $1.totalBytes }
        let free = volumes.reduce(UInt64(0)) { $0 + $1.freeBytes }
        return (Double(total), Double(free))
    }

    private static func percent(used: Double, total: Double) -> Double? {
        guard total > 0, used.isFinite, total.isFinite else { return nil }
        return min(100, max(0, used / total * 100))
    }

    private static func derivedReading(
        _ value: Double?,
        for metric: MenuBarMetricID
    ) -> MenuBarMetricReading {
        guard let value else {
            return MenuBarMetricReading(text: dash, value: nil,
                                        availability: .temporarilyUnavailable)
        }
        return MenuBarMetricReading(
            text: MenuBarMetricRegistry.format(value, for: metric),
            value: value,
            availability: .measured
        )
    }

}
