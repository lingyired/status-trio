import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// Reproduces the "reopen the panel: temperature text has a value but its bar
/// stays all grey until the next sensor tick" report. The bar must show a fill
/// on the very first frame that carries a measured value.
@MainActor
final class HardwareMonitorBarLatencyTests: XCTestCase {
    private func makeHost(_ model: HardwareMonitorObservable,
                          localization: Localization) -> NSHostingView<AnyView> {
        let host = NSHostingView(rootView: AnyView(HardwareMonitorCardView(model: model)
            .environmentObject(localization)
            .frame(width: 302)))
        host.frame = NSRect(x: 0, y: 0, width: 302, height: 84)
        host.layoutSubtreeIfNeeded()
        return host
    }

    /// Count accent-coloured (blue) pixels in the lower-left quadrant, which is
    /// the temperature tile's progress track.
    private func temperatureFillPixels(_ host: NSHostingView<AnyView>) throws -> Int {
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        var count = 0
        for y in (height / 2)..<height {
            for x in 0..<(width / 2) {
                guard let color = bitmap.colorAt(x: x, y: y)?
                    .usingColorSpace(.deviceRGB) else { continue }
                // System accent blue: clearly more blue than red/green.
                if color.blueComponent > 0.55,
                   color.blueComponent > color.redComponent + 0.25,
                   color.greenComponent > 0.15 {
                    count += 1
                }
            }
        }
        return count
    }

    private func measuredTemperature(_ celsius: Double, at date: Date = Date()) -> HardwareMetricsSnapshot {
        HardwareMetricsSnapshot(samples: [
            .cpuTemperature: HardwareMetricSample(value: celsius, unit: .celsius,
                                                  sampledAt: date, source: .smc,
                                                  availability: .measured)
        ])
    }

    func testReopenedCardShowsTemperatureFillOnFirstMeasuredFrame() throws {
        let suite = "StatusTrioCoreTests.BarLatency.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let model = HardwareMonitorObservable()
        let host = makeHost(model, localization: localization)

        // Panel just reopened: no samples yet (service clears on close).
        _ = try temperatureFillPixels(host)
        model.update(measuredTemperature(62))
        // SwiftUI applies the state change on the next run-loop turn; the fill
        // must be there immediately after that turn, not only on the next
        // 4-second sensor tick (the reported bug).
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertGreaterThan(try temperatureFillPixels(host), 20,
                             "measured temperature must paint its bar on the first update")

        // A later tick must keep or grow the fill, never reset it.
        model.update(measuredTemperature(70))
        XCTAssertGreaterThan(try temperatureFillPixels(host), 20)
    }

    func testClosedThenReopenedCardRecoversFillImmediately() throws {
        let suite = "StatusTrioCoreTests.BarLatency2.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let model = HardwareMonitorObservable()
        let host = makeHost(model, localization: localization)

        model.update(measuredTemperature(62))
        _ = try temperatureFillPixels(host)
        // Panel closes: the service clears the observable.
        model.clear()
        _ = try temperatureFillPixels(host)
        // Panel reopens and the first sensor read lands.
        model.update(measuredTemperature(64))
        XCTAssertGreaterThan(try temperatureFillPixels(host), 20,
                             "reopening must not leave the temperature bar grey")
    }
}