import Foundation

/// Fixed identity of one of the four compact summary slots under the rings.
enum HardwareSummaryMetric: String, CaseIterable, Sendable {
    case download, upload, fan, disk
}

/// Everything the compact summary row needs to draw one slot, with formatting
/// and unavailable-state semantics kept pure so they are testable without a view.
struct HardwareSummaryMetricPresentation: Equatable {
    let metric: HardwareSummaryMetric
    let valueText: String
    let unitText: String
    let symbol: String
    let accessibilityLabel: String
    let accessibilityValue: String
    let help: String
    let isStale: Bool
    let availability: HardwareMetricAvailability
}

/// Builds the fixed four-slot summary (download, upload, average fan, disk I/O).
/// Values can be missing, so a slot never invents a number: it shows an em dash
/// and explains why. Disk read and write always share one unit chosen from their
/// larger magnitude, so two different quantities are never under one label.
@MainActor
enum HardwareMonitorSummaryPresentation {
    private static let dash = "—"

    @MainActor
    static func items(snapshot: HardwareMetricsSnapshot,
                      localization: Localization) -> [HardwareSummaryMetricPresentation] {
        [
            networkItem(.download, sample: snapshot.networkDownload, symbol: "arrow.down",
                        label: .hardwareMonitorDownload, help: .hardwareMonitorDownloadHelp,
                        localization: localization),
            networkItem(.upload, sample: snapshot.networkUpload, symbol: "arrow.up",
                        label: .hardwareMonitorUpload, help: .hardwareMonitorUploadHelp,
                        localization: localization),
            fanItem(snapshot: snapshot, localization: localization),
            diskItem(snapshot: snapshot, localization: localization),
        ]
    }

    // MARK: - Formatters

    /// Byte-rate unit chosen by magnitude. Decimal (1 000-based) so the label
    /// matches the KB/s, MB/s glyphs already used by the network tiles.
    private struct UnitScale {
        let divisor: Double
        let key: LocalizationKey
    }

    private static func scale(for bytesPerSecond: Double) -> UnitScale {
        let magnitude = abs(bytesPerSecond)
        if magnitude >= 1_000_000_000 { return UnitScale(divisor: 1_000_000_000, key: .hardwareMonitorGBps) }
        if magnitude >= 1_000_000 { return UnitScale(divisor: 1_000_000, key: .hardwareMonitorMBps) }
        return UnitScale(divisor: 1_000, key: .hardwareMonitorKBps)
    }

    /// Decimal number capped at three significant digits, trailing zeros trimmed:
    /// 2 000 000 → "2", 500 000 → "0.5", 18.4 → "18.4", 184 → "184".
    static func number(_ value: Double) -> String {
        let magnitude = abs(value)
        let raw: String
        if magnitude >= 100 { raw = String(format: "%.0f", value) }
        else if magnitude >= 10 { raw = String(format: "%.1f", value) }
        else if magnitude >= 1 { raw = String(format: "%.2f", value) }
        else { raw = String(format: "%.3f", value) }
        guard raw.contains(".") else { return raw }
        var trimmed = raw
        while trimmed.hasSuffix("0") { trimmed.removeLast() }
        if trimmed.hasSuffix(".") { trimmed.removeLast() }
        return trimmed
    }

    /// Numeric value eligible for display (measured or cached-stale), else nil.
    private static func displayValue(_ sample: HardwareMetricSample) -> Double? {
        guard sample.availability == .measured || sample.availability == .stale,
              let value = sample.value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func reasonText(_ sample: HardwareMetricSample, localization: Localization) -> String {
        switch sample.availability {
        case .collecting: localization.string(.hardwareMonitorCollecting)
        case .unsupported: localization.string(.hardwareMonitorUnsupported)
        case .stale: localization.string(.hardwareMonitorStale)
        case .temporarilyUnavailable, .measured: localization.string(.hardwareMonitorUnavailable)
        }
    }

    // MARK: - Slots

    private static func networkItem(_ metric: HardwareSummaryMetric, sample: HardwareMetricSample,
                                    symbol: String, label: LocalizationKey, help: LocalizationKey,
                                    localization: Localization) -> HardwareSummaryMetricPresentation {
        let value = displayValue(sample)
        var valueText = dash
        var unitText = ""
        var accessibilityValue = reasonText(sample, localization: localization)
        if let value {
            let unit = scale(for: value)
            valueText = number(value / unit.divisor)
            unitText = localization.string(unit.key)
            accessibilityValue = accessibilityValue.isEmpty ? "\(valueText) \(unitText)"
                : "\(valueText) \(unitText)"
        }
        return HardwareSummaryMetricPresentation(
            metric: metric, valueText: valueText, unitText: unitText, symbol: symbol,
            accessibilityLabel: localization.string(label), accessibilityValue: accessibilityValue,
            help: localization.string(help), isStale: sample.availability == .stale,
            availability: sample.availability)
    }

    private static func fanItem(snapshot: HardwareMetricsSnapshot,
                                localization: Localization) -> HardwareSummaryMetricPresentation {
        let sample = snapshot.averageFanSample
        let value = displayValue(sample)
        var valueText = dash
        var unitText = ""
        var accessibilityValue = reasonText(sample, localization: localization)
        if let value {
            valueText = String(Int(value.rounded()))
            unitText = "RPM"
            accessibilityValue = "\(valueText) \(unitText)"
        } else if sample.availability == .unsupported && sample.metadata.isFanless {
            valueText = localization.string(.hardwareMonitorFanless)
            accessibilityValue = valueText
        }
        return HardwareSummaryMetricPresentation(
            metric: .fan, valueText: valueText, unitText: unitText, symbol: "fanblades",
            accessibilityLabel: localization.string(.hardwareMonitorFanAverage),
            accessibilityValue: accessibilityValue,
            help: localization.string(.hardwareMonitorFanAverageHelp),
            isStale: sample.availability == .stale, availability: sample.availability)
    }

    private static func diskItem(snapshot: HardwareMetricsSnapshot,
                                 localization: Localization) -> HardwareSummaryMetricPresentation {
        let read = displayValue(snapshot.diskRead)
        let write = displayValue(snapshot.diskWrite)
        let stale = snapshot.diskRead.availability == .stale || snapshot.diskWrite.availability == .stale
        var valueText = dash
        var unitText = ""
        var accessibilityValue = reasonText(snapshot.diskRead, localization: localization)
        if read != nil || write != nil {
            let unit = scale(for: max(read ?? 0, write ?? 0))
            let readText = read.map { number($0 / unit.divisor) } ?? dash
            let writeText = write.map { number($0 / unit.divisor) } ?? dash
            valueText = "\(readText)/\(writeText)"
            unitText = localization.string(unit.key)
            let readFull = read.map { "\(number($0 / unit.divisor)) \(unitText)" } ?? dash
            let writeFull = write.map { "\(number($0 / unit.divisor)) \(unitText)" } ?? dash
            let readLabel = localization.string(.hardwareMonitorDiskRead)
            let writeLabel = localization.string(.hardwareMonitorDiskWrite)
            accessibilityValue = "\(readLabel) \(readFull), \(writeLabel) \(writeFull)"
        }
        return HardwareSummaryMetricPresentation(
            metric: .disk, valueText: valueText, unitText: unitText, symbol: "internaldrive",
            accessibilityLabel: localization.string(.hardwareMonitorDisk),
            accessibilityValue: accessibilityValue,
            help: localization.string(.hardwareMonitorDiskHelp),
            isStale: stale,
            availability: snapshot.diskRead.availability)
    }
}
