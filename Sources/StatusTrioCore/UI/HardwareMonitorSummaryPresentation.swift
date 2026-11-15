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
/// Rates use the shared Auto formatter; a slot never invents a number, showing an
/// em dash and explaining why when data is missing. Disk shows the read+write
/// total only when both directions come from the same valid sample.
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

    private static func networkItem(_ metric: HardwareSummaryMetric, sample: HardwareMetricSample,
                                    symbol: String, label: LocalizationKey, help: LocalizationKey,
                                    localization: Localization) -> HardwareSummaryMetricPresentation {
        let value = displayValue(sample)
        var valueText = dash
        var unitText = ""
        var accessibilityValue = reasonText(sample, localization: localization)
        if let value, let display = ByteRateFormatter.format(bytesPerSecond: value) {
            valueText = display.valueText
            unitText = display.unitText
            accessibilityValue = display.combined
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
        var help = localization.string(.hardwareMonitorFanAverageHelp)
        if let value {
            valueText = String(Int(value.rounded()))
            unitText = "RPM"
            accessibilityValue = "\(valueText) \(unitText)"
            if let fanCount = snapshot.fanCount, fanCount > 1,
               let count = sample.metadata.sourceCount, count > 0, count < fanCount {
                help += " " + localization.format(.hardwareMonitorFanSampleCount, count)
                accessibilityValue += "，" + localization.format(.hardwareMonitorFanSampleCount, count)
            }
        } else if sample.availability == .unsupported && sample.metadata.isFanless {
            valueText = localization.string(.hardwareMonitorFanless)
            accessibilityValue = valueText
        }
        return HardwareSummaryMetricPresentation(
            metric: .fan, valueText: valueText, unitText: unitText, symbol: "fanblades",
            accessibilityLabel: localization.string(.hardwareMonitorFanAverage),
            accessibilityValue: accessibilityValue,
            help: help, isStale: sample.availability == .stale, availability: sample.availability)
    }

    private static func diskItem(snapshot: HardwareMetricsSnapshot,
                                 localization: Localization) -> HardwareSummaryMetricPresentation {
        let readSample = snapshot.diskRead
        let writeSample = snapshot.diskWrite
        let read = displayValue(readSample)
        let write = displayValue(writeSample)
        let readLabel = localization.string(.hardwareMonitorDiskRead)
        let writeLabel = localization.string(.hardwareMonitorDiskWrite)
        let totalLabel = localization.string(.hardwareMonitorDiskTotal)
        let sameCycle = read != nil && write != nil
            && readSample.availability == writeSample.availability
            && readSample.sampledAt == writeSample.sampledAt
        var valueText = dash
        var unitText = ""
        var accessibilityValue: String
        var help: String
        var isStale = false
        if sameCycle, let read, let write,
           let total = ByteRateFormatter.format(bytesPerSecond: read + write) {
            let readText = ByteRateFormatter.text(bytesPerSecond: read) ?? dash
            let writeText = ByteRateFormatter.text(bytesPerSecond: write) ?? dash
            valueText = total.valueText
            unitText = total.unitText
            help = "\(readLabel) \(readText) · \(writeLabel) \(writeText)"
            accessibilityValue =
                "\(readLabel) \(readText)，\(writeLabel) \(writeText)，\(totalLabel) \(total.combined)"
            isStale = readSample.availability == .stale
        } else {
            let readText = read.map { ByteRateFormatter.text(bytesPerSecond: $0) ?? dash } ?? dash
            let writeText = write.map { ByteRateFormatter.text(bytesPerSecond: $0) ?? dash } ?? dash
            help = "\(readLabel) \(readText) · \(writeLabel) \(writeText)"
            let reasonSample = read != nil ? writeSample : readSample
            accessibilityValue = "\(totalLabel) —，\(reasonText(reasonSample, localization: localization))"
            isStale = false
        }
        return HardwareSummaryMetricPresentation(
            metric: .disk, valueText: valueText, unitText: unitText, symbol: "internaldrive",
            accessibilityLabel: localization.string(.hardwareMonitorDisk),
            accessibilityValue: accessibilityValue, help: help, isStale: isStale,
            availability: readSample.availability)
    }
}
