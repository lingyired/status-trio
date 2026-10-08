import XCTest
@testable import StatusTrioCore

final class IconSourceAvailabilityTests: XCTestCase {
    func testAvailabilityValuesDistinguishZeroLikeDataFromUnavailable() {
        let availableZero = SourceResult<Int>.available(0)
        let unavailable = SourceResult<Int>.unavailable(.disconnected)

        XCTAssertEqual(availableZero, .available(0))
        XCTAssertNotEqual(availableZero, unavailable)
    }

    func testEmptySnapshotHasNoOverrides() {
        XCTAssertTrue(IconSourceSnapshot.empty.availability.isEmpty)
    }

    func testSnapshotUsesExplicitAvailabilityForSource() {
        let snapshot = IconSourceSnapshot(availability: [
            CenterSource.bluetoothAudioOutput.rawValue: .unavailable(.permissionDenied)
        ])

        XCTAssertEqual(
            snapshot.result(for: CenterSource.bluetoothAudioOutput.rawValue, default: .available(true)),
            .unavailable(.permissionDenied)
        )
        XCTAssertEqual(
            snapshot.result(for: CenterSource.network.rawValue, default: .available(true)),
            .available(true)
        )
    }
}
