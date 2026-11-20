import XCTest
@testable import StatusTrioCore

final class HardwareRingValuePresentationTests: XCTestCase {
    private let gib: UInt64 = 1_073_741_824

    func testMemoryUsedModeShowsConsumedAmountAndPercent() {
        let spec = HardwareRingValuePresentation.memory(
            usedPercent: 50, totalBytes: 128 * gib, mode: .used)
        XCTAssertEqual(spec.topText, "50%")
        XCTAssertEqual(spec.centerText, "64GB")
        XCTAssertEqual(spec.progress, 0.5, accuracy: 0.0001)
    }

    func testMemoryRemainingModeShowsFreeAmountAndPercent() {
        let spec = HardwareRingValuePresentation.memory(
            usedPercent: 25, totalBytes: 128 * gib, mode: .remaining)
        XCTAssertEqual(spec.topText, "75%")
        XCTAssertEqual(spec.centerText, "96GB")
        XCTAssertEqual(spec.progress, 0.75, accuracy: 0.0001)
    }

    func testMemoryMissingSampleIsPlaceholderNotZero() {
        let spec = HardwareRingValuePresentation.memory(
            usedPercent: nil, totalBytes: 128 * gib, mode: .used)
        XCTAssertEqual(spec.topText, "0%")
        XCTAssertEqual(spec.centerText, "--")
        XCTAssertEqual(spec.progress, 0)
    }

    func testDiskUsedModeShowsTotalMinusFree() {
        let total: Int64 = 1_000_000_000_000
        let free: Int64 = 250_000_000_000
        let spec = HardwareRingValuePresentation.disk(
            usedFraction: 0.75, totalBytes: total, freeBytes: free, mode: .used)
        XCTAssertEqual(spec.topText, "75%")
        XCTAssertEqual(spec.centerText, "750GB")
        XCTAssertEqual(spec.progress, 0.75, accuracy: 0.0001)
    }

    func testDiskRemainingModeShowsFreeAndRemainingPercent() {
        let total: Int64 = 1_000_000_000_000
        let free: Int64 = 250_000_000_000
        let spec = HardwareRingValuePresentation.disk(
            usedFraction: 0.75, totalBytes: total, freeBytes: free, mode: .remaining)
        XCTAssertEqual(spec.topText, "25%")
        XCTAssertEqual(spec.centerText, "250GB")
        XCTAssertEqual(spec.progress, 0.25, accuracy: 0.0001)
    }

    func testDiskWithoutCapacityStillReportsPercent() {
        let spec = HardwareRingValuePresentation.disk(
            usedFraction: 0.5, totalBytes: nil, freeBytes: nil, mode: .used)
        XCTAssertEqual(spec.topText, "50%")
        XCTAssertEqual(spec.centerText, "--")
    }

    func testMemoryUsesBinaryGiBSoInstalledRAMReads128() {
        let bytes = Double(128 * gib)
        XCTAssertEqual(HardwareDetailFormat.compactMemory(bytes), "128GB")
        XCTAssertEqual(HardwareDetailFormat.memoryBytes(UInt64(128 * gib)), "128.0 GB")
    }

    func testDiskStaysDecimal() {
        XCTAssertEqual(HardwareDetailFormat.compactDisk(1_000_000_000_000), "1000GB")
    }
}
