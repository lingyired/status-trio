import XCTest
@testable import StatusTrioCore

final class ByteRateFormatterTests: XCTestCase {
    private func display(_ bytes: Double) -> String? {
        ByteRateFormatter.format(bytesPerSecond: bytes).map { "\($0.valueText) \($0.unitText)" }
    }

    func testZeroAndSubKilobyteReadAsZeroKilobytes() {
        XCTAssertEqual(display(0), "0 KB/s")
        XCTAssertEqual(display(999), "0 KB/s")
        XCTAssertEqual(display(1_000), "1 KB/s")
    }

    func testKilobyteRangeUsesWholeNumbers() {
        XCTAssertEqual(display(456_000), "456 KB/s")
        XCTAssertEqual(display(999_000), "999 KB/s")
        XCTAssertEqual(display(999_600), "1.0 MB/s")
    }

    func testMegabyteRangeBelow100UsesOneDecimal() {
        XCTAssertEqual(display(1_000_000), "1.0 MB/s")
        XCTAssertEqual(display(12_500_000), "12.5 MB/s")
        XCTAssertEqual(display(99_900_000), "99.9 MB/s")
        XCTAssertEqual(display(99_960_000), "100 MB/s")
    }

    func testMegabyteRange100To1000UsesWholeNumbers() {
        XCTAssertEqual(display(125_000_000), "125 MB/s")
        XCTAssertEqual(display(999_400_000), "999 MB/s")
    }

    func testGigabyteAndTerabyteRange() {
        XCTAssertEqual(display(1_300_000_000), "1.3 GB/s")
        XCTAssertEqual(display(12_500_000_000), "12.5 GB/s")
        XCTAssertEqual(display(2_000_000_000_000), "2.0 TB/s")
    }

    func testUndisplayableValuesReturnNil() {
        XCTAssertNil(ByteRateFormatter.format(bytesPerSecond: -1))
        XCTAssertNil(ByteRateFormatter.format(bytesPerSecond: .nan))
        XCTAssertNil(ByteRateFormatter.format(bytesPerSecond: .infinity))
        XCTAssertNil(ByteRateFormatter.text(bytesPerSecond: -5))
    }

    func testCompactGlyphUsesSameUnitSelection() {
        XCTAssertEqual(ByteRateFormatter.compact(bytesPerSecond: 456_000), "456K")
        XCTAssertEqual(ByteRateFormatter.compact(bytesPerSecond: 12_500_000), "12.5M")
        XCTAssertEqual(ByteRateFormatter.compact(bytesPerSecond: 1_300_000_000), "1.3G")
        XCTAssertEqual(ByteRateFormatter.compact(bytesPerSecond: 2_000_000_000_000), "2.0T")
        XCTAssertEqual(ByteRateFormatter.compact(bytesPerSecond: 0), "0K")
    }
}
