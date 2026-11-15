import XCTest
import SwiftUI
@testable import StatusTrioCore

/// Offscreen sizing only: no window is ever created or ordered on screen.
@MainActor
final class HardwareMonitorSummaryLayoutTests: XCTestCase {
    private func makeLocalization() -> Localization {
        let suite = "HardwareMonitorSummaryLayoutTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return Localization(defaults: defaults, preferredLanguages: ["en"])
    }

    private func snapshot(_ availability: HardwareMetricAvailability) -> HardwareMetricsSnapshot {
        var snapshot = HardwareMetricsSnapshot(fanCount: 2)
        func sample(_ unit: HardwareMetricUnit, _ value: Double?, _ source: HardwareMetricSource) -> HardwareMetricSample {
            HardwareMetricSample(value: value, unit: unit, sampledAt: Date(), source: source,
                                 availability: availability)
        }
        snapshot.samples[.cpuUsage] = sample(.percent, 61, .mach)
        snapshot.samples[.gpuUsage] = sample(.percent, 72, .ioAccelerator)
        snapshot.samples[.memoryUsage] = sample(.percent, 51, .mach)
        snapshot.samples[.cpuTemperature] = sample(.celsius, 61, .smc)
        snapshot.samples[.gpuTemperature] = sample(.celsius, 72, .smc)
        snapshot.samples[.fanRPM(index: 0)] = sample(.rpm, 2036, .smc)
        snapshot.samples[.networkDownload] = sample(.bytesPerSecond, 1_820_000, .network)
        snapshot.samples[.networkUpload] = sample(.bytesPerSecond, 184_000, .network)
        snapshot.samples[.diskRead] = sample(.bytesPerSecond, 18_400_000, .ioStorage)
        snapshot.samples[.diskWrite] = sample(.bytesPerSecond, 6_200_000, .ioStorage)
        return snapshot
    }



    private func wideSnapshot(_ wide: Bool) -> HardwareMetricsSnapshot {
        var s = HardwareMetricsSnapshot(fanCount: 1)
        func bytes(_ normal: Double, _ big: Double) -> HardwareMetricSample {
            HardwareMetricSample(value: wide ? big : normal, unit: .bytesPerSecond,
                                 sampledAt: Date(), source: .ioStorage, availability: .measured)
        }
        s.samples[.cpuUsage] = HardwareMetricSample(value: 61, unit: .percent, sampledAt: Date(), source: .mach, availability: .measured)
        s.samples[.gpuUsage] = HardwareMetricSample(value: 72, unit: .percent, sampledAt: Date(), source: .mach, availability: .measured)
        s.samples[.memoryUsage] = HardwareMetricSample(value: 51, unit: .percent, sampledAt: Date(), source: .mach, availability: .measured)
        s.samples[.cpuTemperature] = HardwareMetricSample(value: 61, unit: .celsius, sampledAt: Date(), source: .smc, availability: .measured)
        s.samples[.gpuTemperature] = HardwareMetricSample(value: 72, unit: .celsius, sampledAt: Date(), source: .smc, availability: .measured)
        s.samples[.fanRPM(index: 0)] = HardwareMetricSample(value: wide ? 987654 : 2036, unit: .rpm, sampledAt: Date(), source: .smc, availability: .measured)
        s.samples[.networkDownload] = bytes(1_820_000, 9_876_543_210)
        s.samples[.networkUpload] = bytes(184_000, 8_765_432_100)
        s.samples[.diskRead] = bytes(18_400_000, 9_999_999_999)
        s.samples[.diskWrite] = bytes(6_200_000, 8_888_888_888)
        return s
    }

    private func fittingHeight(_ snapshot: HardwareMetricsSnapshot) -> CGFloat {
        let host = NSHostingView(rootView: HardwareMonitorSummaryView(model: HardwareMonitorObservable(snapshot: snapshot))
            .environmentObject(makeLocalization())
            .frame(width: 302))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }


    private func presentation(_ valueText: String, unit: String) -> HardwareSummaryMetricPresentation {
        HardwareSummaryMetricPresentation(
            metric: .disk, valueText: valueText, unitText: unit, symbol: "internaldrive",
            accessibilityLabel: "Disk", accessibilityValue: valueText, help: "",
            isStale: false, availability: .measured)
    }

    private func cellHeight(_ valueText: String) -> CGFloat {
        let host = NSHostingView(rootView: HardwareSummaryMetricCell(item: presentation(valueText, unit: "GB/s"))
            .frame(width: 63))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    func testCellHeightUnaffectedByShrinkingLongValue() {
        let short = cellHeight("18.4/6.2")
        let long = cellHeight("9999999999/8888888888")
        XCTAssertEqual(short, long, accuracy: 0.5,
                       "a value shrunk to fit must not change the cell height or move the icon row")
    }

    func testSummaryHeightStableWhenAllValuesAreLong() {
        let normal = fittingHeight(wideSnapshot(false))
        let wide = fittingHeight(wideSnapshot(true))
        XCTAssertEqual(normal, wide, accuracy: 0.5,
                       "all four values shrinking must not change the summary height")
    }

    func testFitsPanelWidthAndStaysCompactAcrossLanguagesAndStates() {
        let localization = makeLocalization()
        for language in AppLanguage.allCases {
            localization.setPreference(.language(language))
            for availability in [HardwareMetricAvailability.measured, .collecting,
                                 .unsupported, .temporarilyUnavailable, .stale] {
                let model = HardwareMonitorObservable(snapshot: snapshot(availability))
                let host = NSHostingView(rootView: HardwareMonitorSummaryView(model: model)
                    .environmentObject(localization)
                    .frame(width: 302))
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(host.fittingSize.width, 302, accuracy: 0.5, "\(language) \(availability)")
                XCTAssertLessThan(host.fittingSize.height, 170, "\(language) \(availability) too tall")
                XCTAssertGreaterThan(host.fittingSize.height, 90, "\(language) \(availability) too short")
                XCTAssertNil(host.window)
            }
        }
    }
}
