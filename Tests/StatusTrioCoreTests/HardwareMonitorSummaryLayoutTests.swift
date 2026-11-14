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
