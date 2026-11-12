import XCTest
@testable import StatusTrioCore

final class NetworkThroughputTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    func testRateMathFromByteDeltas() throws {
        let previous = InterfaceByteTotals(received: 1_000_000, sent: 200_000)
        let current = InterfaceByteTotals(received: 13_500_000, sent: 700_000)
        let reading = try XCTUnwrap(NetworkThroughputReader.rates(
            previous: previous, previousAt: base,
            current: current, currentAt: base.addingTimeInterval(1)
        ))
        XCTAssertEqual(reading.downloadBytesPerSecond, 12_500_000, accuracy: 1)
        XCTAssertEqual(reading.uploadBytesPerSecond, 500_000, accuracy: 1)
    }

    func testRateRejectsTooSmallOrTooLargeInterval() {
        let p = InterfaceByteTotals(received: 0, sent: 0)
        let c = InterfaceByteTotals(received: 1000, sent: 1000)
        XCTAssertNil(NetworkThroughputReader.rates(previous: p, previousAt: base, current: c, currentAt: base.addingTimeInterval(0.05)))
        XCTAssertNil(NetworkThroughputReader.rates(previous: p, previousAt: base, current: c, currentAt: base.addingTimeInterval(60)))
    }

    func testRateRejectsCounterReset() {
        let p = InterfaceByteTotals(received: 5_000_000, sent: 5_000_000)
        let c = InterfaceByteTotals(received: 10, sent: 10)
        XCTAssertNil(NetworkThroughputReader.rates(previous: p, previousAt: base, current: c, currentAt: base.addingTimeInterval(1)))
    }

    func testFormatterSwitchesBetweenKBAndMB() {
        XCTAssertEqual(NetworkSpeedFormatter.display(bytesPerSecond: 456_000), "456 KB/s")
        XCTAssertEqual(NetworkSpeedFormatter.display(bytesPerSecond: 12_500_000), "12.5 MB/s")
        XCTAssertEqual(NetworkSpeedFormatter.compact(bytesPerSecond: 456_000), "456K")
        XCTAssertEqual(NetworkSpeedFormatter.compact(bytesPerSecond: 12_500_000), "12.5M")
        XCTAssertEqual(NetworkSpeedFormatter.displayWithBits(bytesPerSecond: 12_500_000), "12.5 MB/s · 100 Mbps")
    }

    func testProgressUsesCapInMbps() throws {
        let sample = HardwareMetricSample(value: 12_500_000, unit: .bytesPerSecond,
                                          sampledAt: base, source: .network, availability: .measured)
        // 12.5 MB/s == 100 Mbps; cap 1000 → 0.1
        XCTAssertEqual(try XCTUnwrap(MetricProgressMapper.speed(sample, capMbps: 1000)), 0.1, accuracy: 0.0001)
        XCTAssertNil(MetricProgressMapper.speed(sample, capMbps: 0))
    }

    func testRingMapperSpeedProgressAndCompactTopValue() {
        var snapshot = HardwareMetricsSnapshot()
        snapshot.samples[.networkDownload] = HardwareMetricSample(
            value: 12_500_000, unit: .bytesPerSecond, sampledAt: base, source: .network, availability: .measured)
        let configuration = HardwareRingConfiguration(
            layout: .single, primaryMetric: .downloadSpeed, topContent: .value(.downloadSpeed),
            color: HardwareRingColorConfiguration(monochrome: false, thresholdColors: true)
        )
        let state = HardwareRingMapper.resolve(snapshot: snapshot, configuration: configuration,
                                                speedCapsMbps: [.downloadSpeed: 1000], now: base)
        XCTAssertEqual(state.segments[0].progress, 0.1, accuracy: 0.0001)
        guard case let .text(text)? = state.accessory else { return XCTFail("expected text") }
        XCTAssertEqual(text.text, "12.5M")
    }

    @MainActor
    func testSpeedCapsDefaultsClampAndPersist() throws {
        let name = "StatusTrioCoreTests.NetSpeed.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.hardwareDownloadCapMbps, 1000, accuracy: 0.001)
        XCTAssertEqual(store.hardwareUploadCapMbps, 100, accuracy: 0.001)
        store.hardwareDownloadCapMbps = 0
        XCTAssertEqual(store.hardwareDownloadCapMbps, 1, accuracy: 0.001)
        store.hardwareUploadCapMbps = 500
        let reopened = SettingsStore(defaults: defaults)
        XCTAssertEqual(reopened.hardwareUploadCapMbps, 500, accuracy: 0.001)
    }
}
