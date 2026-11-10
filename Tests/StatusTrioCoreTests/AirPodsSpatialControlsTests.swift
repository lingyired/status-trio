import XCTest
@testable import StatusTrioCore

final class AirPodsSpatialControlsTests: XCTestCase {
    func testSavedAutomaticModeDoesNotPretendStereoIsSpatialized() {
        XCTAssertEqual(AirPodsSpatialState.mode(configuration: [1,0,0,0,1,0,0,0], active: false), .off)
        XCTAssertEqual(AirPodsSpatialState.mode(configuration: [2,0,0,0,0,0,0,0], active: true), .fixed)
        XCTAssertEqual(AirPodsSpatialState.mode(configuration: [2,0,0,0,1,0,0,0], active: true), .headTracked)
        XCTAssertNil(AirPodsSpatialState.mode(configuration: [9,0,0,0,1,0,0,0], active: true))
        XCTAssertNil(AirPodsSpatialState.mode(configuration: [2,0,0,0,2,0,0,0], active: true))
        XCTAssertNil(AirPodsSpatialState.mode(configuration: [2,0], active: true))
    }
    func testCommandsArePIDScopedAndNeverUseAZeroClient() {
        XCTAssertNil(AirPodsSpatialState.command(.fixed, pid: 0))
        XCTAssertEqual(AirPodsSpatialState.command(.fixed, pid: 0x1234), [0x34,0x12,0,0,0,1,0,0])
        XCTAssertEqual(AirPodsSpatialState.command(.headTracked, pid: 0x1234), [0x34,0x12,0,0,1,1,0,0])
    }
    @MainActor
    func testRouteValidationStopsSpatialWriteBeforeHardwareAccess() async {
        var checked = false
        do {
            _ = try await AirPodsSpatialControls(deviceID: 0).set(.fixed,
                expected: .init(pid: 1, bundleID: "test", mode: .off)) {
                    checked = true
                    throw AirPodsSystemControlError.routeChanged
                }
            XCTFail("Changed route must not reach hardware")
        } catch {
            XCTAssertEqual(error as? AirPodsSystemControlError, .routeChanged)
        }
        XCTAssertTrue(checked)
    }

    @MainActor
    func testCancelledSpatialReadStopsBeforeHardwareAccess() async {
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try AirPodsSpatialControls(deviceID: 0).read()
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

}
