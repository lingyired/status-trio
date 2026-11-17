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
        let ts = Date(timeIntervalSince1970: 1_000)
        func sample(_ unit: HardwareMetricUnit, _ value: Double?, _ source: HardwareMetricSource) -> HardwareMetricSample {
            HardwareMetricSample(value: value, unit: unit, sampledAt: ts, source: source,
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



    func testFourCardLayoutFits302WidthAndVisibilityCombinations() {
        let localization = makeLocalization()
        let base = snapshot(.measured)
        func host(rings: Bool, row: Bool) -> NSHostingView<AnyView> {
            NSHostingView(rootView: AnyView(
                HardwareMonitorSummaryView(model: HardwareMonitorObservable(snapshot: base),
                                           showsRings: rings, showsSummaryRow: row)
                    .environmentObject(localization)
                    .frame(width: 302)))
        }
        let both = host(rings: true, row: true)
        both.layoutSubtreeIfNeeded()
        XCTAssertEqual(both.fittingSize.width, 302, accuracy: 0.5, "four cards must fit 302 pt without scrolling")
        XCTAssertGreaterThan(both.fittingSize.height, 90)
        XCTAssertLessThan(both.fittingSize.height, 170)

        let ringsOnly = host(rings: true, row: false)
        ringsOnly.layoutSubtreeIfNeeded()
        XCTAssertEqual(ringsOnly.fittingSize.width, 302, accuracy: 0.5)
        XCTAssertGreaterThan(ringsOnly.fittingSize.height, 60)

        let rowOnly = host(rings: false, row: true)
        rowOnly.layoutSubtreeIfNeeded()
        XCTAssertEqual(rowOnly.fittingSize.width, 302, accuracy: 0.5)
        XCTAssertGreaterThan(rowOnly.fittingSize.height, 20)
        XCTAssertLessThan(rowOnly.fittingSize.height, 60)

        let none = host(rings: false, row: false)
        none.layoutSubtreeIfNeeded()
        XCTAssertLessThan(none.fittingSize.height, 5, "both blocks hidden renders nothing")
    }

    func testCardSurfacesAndAppearancesKeepStableSize() {
        let localization = makeLocalization()
        let base = snapshot(.measured)
        for style in [PanelCardSurfaceStyle.glass, .material, .solid] {
            for dark in [false, true] {
                let host = NSHostingView(rootView: AnyView(
                    HardwareMonitorSummaryView(model: HardwareMonitorObservable(snapshot: base))
                        .environmentObject(localization)
                        .environment(\.panelCardSurfaceStyle, style)
                        .environment(\.colorScheme, dark ? .dark : .light)
                        .frame(width: 302)))
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(host.fittingSize.width, 302, accuracy: 0.5, "\(style) \(dark)")
                XCTAssertGreaterThan(host.fittingSize.height, 90, "\(style) \(dark)")
                XCTAssertLessThan(host.fittingSize.height, 170, "\(style) \(dark)")
            }
        }
    }

    func testHeightStableAcrossRateBoundariesZeroAndDash() {
        let ts = Date(timeIntervalSince1970: 1_000)
        func snap(_ net: Double?, _ availability: HardwareMetricAvailability = .measured) -> HardwareMetricsSnapshot {
            var s = HardwareMetricsSnapshot(fanCount: 1)
            func sample(_ unit: HardwareMetricUnit, _ value: Double?, _ source: HardwareMetricSource) -> HardwareMetricSample {
                HardwareMetricSample(value: value, unit: unit, sampledAt: ts, source: source, availability: availability)
            }
            s.samples[.cpuUsage] = sample(.percent, 61, .mach)
            s.samples[.gpuUsage] = sample(.percent, 72, .mach)
            s.samples[.memoryUsage] = sample(.percent, 51, .mach)
            s.samples[.cpuTemperature] = sample(.celsius, 61, .smc)
            s.samples[.gpuTemperature] = sample(.celsius, 72, .smc)
            s.samples[.fanRPM(index: 0)] = sample(.rpm, 2036, .smc)
            s.samples[.networkDownload] = sample(.bytesPerSecond, net, .network)
            s.samples[.networkUpload] = sample(.bytesPerSecond, net, .network)
            s.samples[.diskRead] = sample(.bytesPerSecond, net, .ioStorage)
            s.samples[.diskWrite] = sample(.bytesPerSecond, net, .ioStorage)
            return s
        }
        var heights: [CGFloat] = []
        for value in [0.0, 999, 999_000, 1_000_000, 125_000_000, 1_300_000_000] {
            heights.append(fittingHeight(snap(value)))
        }
        heights.append(fittingHeight(snap(nil, .temporarilyUnavailable)))
        heights.append(fittingHeight(snap(nil, .stale)))
        let first = heights[0]
        for height in heights {
            XCTAssertEqual(height, first, accuracy: 0.5, "summary height must not change with value length/state")
        }
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
