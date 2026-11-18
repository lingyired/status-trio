import XCTest
@testable import StatusTrioCore

final class DiskThroughputReaderTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func totals(_ read: UInt64, _ written: UInt64) -> DiskByteTotals {
        DiskByteTotals(read: read, written: written)
    }

    func testRatesSumsPerDeviceDeltas() throws {
        let previous: [UInt64: DiskByteTotals] = [1: totals(1_000_000, 500_000), 2: totals(2_000_000, 1_000_000)]
        let current: [UInt64: DiskByteTotals] = [1: totals(4_000_000, 1_500_000), 2: totals(5_000_000, 2_000_000)]
        let reading = try XCTUnwrap(DiskThroughputReader.rates(
            previous: previous, previousAt: base,
            current: current, currentAt: base.addingTimeInterval(2)))
        XCTAssertEqual(reading.readBytesPerSecond, 3_000_000, accuracy: 1)
        XCTAssertEqual(reading.writeBytesPerSecond, 1_000_000, accuracy: 1)
    }

    func testRatesZeroDeltaIsRealZero() throws {
        let history: [UInt64: DiskByteTotals] = [7: totals(9_000, 9_000)]
        let reading = try XCTUnwrap(DiskThroughputReader.rates(
            previous: history, previousAt: base, current: history, currentAt: base.addingTimeInterval(1)))
        XCTAssertEqual(reading.readBytesPerSecond, 0, accuracy: 0.0001)
        XCTAssertEqual(reading.writeBytesPerSecond, 0, accuracy: 0.0001)
    }

    func testRatesRejectsTooSmallOrTooLargeInterval() {
        let previous: [UInt64: DiskByteTotals] = [1: totals(0, 0)]
        let current: [UInt64: DiskByteTotals] = [1: totals(1000, 1000)]
        XCTAssertNil(DiskThroughputReader.rates(previous: previous, previousAt: base, current: current, currentAt: base))
        XCTAssertNil(DiskThroughputReader.rates(previous: previous, previousAt: base, current: current, currentAt: base.addingTimeInterval(0.05)))
        XCTAssertNil(DiskThroughputReader.rates(previous: previous, previousAt: base, current: current, currentAt: base.addingTimeInterval(60)))
    }

    func testRatesRejectsCounterReset() {
        let previous: [UInt64: DiskByteTotals] = [1: totals(5_000_000, 5_000_000)]
        let current: [UInt64: DiskByteTotals] = [1: totals(10, 10)]
        XCTAssertNil(DiskThroughputReader.rates(previous: previous, previousAt: base, current: current, currentAt: base.addingTimeInterval(1)))
    }

    func testRatesRejectsDeviceSetChange() {
        let previous: [UInt64: DiskByteTotals] = [1: totals(0, 0)]
        let current: [UInt64: DiskByteTotals] = [1: totals(1000, 1000), 2: totals(500, 500)]
        XCTAssertNil(DiskThroughputReader.rates(previous: previous, previousAt: base, current: current, currentAt: base.addingTimeInterval(1)))
    }

    func testFirstReadHasNoRateUntilBaseline() throws {
        let provider = MutableProvider(totals: [1: totals(1_000_000, 1_000_000)])
        let reader = DiskThroughputReader(provider: { provider.current })
        XCTAssertNil(reader.read(at: base))
        provider.current = [1: totals(4_000_000, 2_000_000)]
        let reading = try XCTUnwrap(reader.read(at: base.addingTimeInterval(1)))
        XCTAssertEqual(reading.readBytesPerSecond, 3_000_000, accuracy: 1)
        XCTAssertEqual(reading.writeBytesPerSecond, 1_000_000, accuracy: 1)
    }

    func testReadFailureClearsBaseline() {
        let provider = MutableProvider(totals: [1: totals(1_000_000, 1_000_000)])
        let reader = DiskThroughputReader(provider: { provider.current })
        XCTAssertNil(reader.read(at: base))
        provider.current = nil
        XCTAssertNil(reader.read(at: base.addingTimeInterval(1)))
        provider.current = [1: totals(9_000_000, 9_000_000)]
        // Baseline was cleared, so the next successful read re-establishes it and yields no rate.
        XCTAssertNil(reader.read(at: base.addingTimeInterval(2)))
    }

    func testResetClearsBaseline() throws {
        let provider = MutableProvider(totals: [1: totals(0, 0)])
        let reader = DiskThroughputReader(provider: { provider.current })
        XCTAssertNil(reader.read(at: base))
        reader.reset()
        provider.current = [1: totals(1_000_000, 1_000_000)]
        XCTAssertNil(reader.read(at: base.addingTimeInterval(1)))
    }
}

private final class MutableProvider {
    var current: [UInt64: DiskByteTotals]?
    init(totals: [UInt64: DiskByteTotals]?) { self.current = totals }
}
