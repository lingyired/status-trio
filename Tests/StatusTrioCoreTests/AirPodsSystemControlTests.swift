import XCTest
@testable import StatusTrioCore

final class AirPodsSystemControlTests: XCTestCase {
    private let target = PanelAudioDeviceID(id: 42, uid: "AA-BB-CC-DD-EE-FF:output")

    private func device(id: UInt32 = 42, uid: String = "AA-BB-CC-DD-EE-FF:output", name: String = "Renamed earbuds",
                        current: Bool = true, model: String = "2024 4c") -> AudioOutputDevice {
        AudioOutputDevice(id: id, name: name, uid: uid, isCurrent: current,
                          transport: .bluetooth, modelUID: model)
    }

    @MainActor
    func testInvalidSliderTargetsNeverReachHardware() async {
        let controls = AirPodsSystemControls(target: target, name: "Test")
        for value in [-10, 5, 110] {
            do { _ = try await controls.setAdaptive(value); XCTFail("Invalid target accepted") }
            catch AirPodsSystemControlError.unavailable {} catch { XCTFail("Unexpected: \(error)") }
        }
    }

    @MainActor
    func testCancelledDiscoveryStopsBeforeHardwareAccess() async {
        let controls = AirPodsSystemControls(target: target, name: "Test")
        let task = Task { @MainActor in
            try Task.checkCancellation()
            return try await controls.read()
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled discovery returned state") }
        catch is CancellationError {} catch { XCTFail("Unexpected: \(error)") }
        controls.stop()
    }

    @MainActor
    func testUnmatchedIdentityCannotOpenChannelOrWrite() async {
        let controls = AirPodsSystemControls(target: target, name: "Test")
        do { _ = try await controls.read(); XCTFail("Unknown target accepted") }
        catch AirPodsSystemControlError.routeChanged {} catch { XCTFail("Unexpected: \(error)") }
        do { _ = try await controls.setAdaptive(50); XCTFail("Unknown target written") }
        catch AirPodsSystemControlError.routeChanged {} catch { XCTFail("Unexpected: \(error)") }
        controls.stop()
    }

    func testTargetRequiresCurrentUniqueAirPodsIdentity() {
        let matches: (PanelAudioDeviceID, String, [AudioOutputDevice]) -> Bool = { target, name, devices in
            AirPodsSystemControlRules.targetIsCurrent(target, name: name, devices: devices, paired: [("AA-BB-CC-DD-EE-FF", "Original device name")])
        }
        XCTAssertTrue(matches(target, "Renamed earbuds", [device()]))
        for paired: [(String, String)] in [[], [("00-11-22-33-44-55", "Renamed earbuds")],
            [("AA-BB-CC-DD-EE-FF", "Old name"), ("00-11-22-33-44-55", "Renamed earbuds")],
            [("AA-BB-CC-DD-EE-FF", "Old name"), ("AA-BB-CC-DD-EE-FF", "Old name")]] {
            XCTAssertFalse(AirPodsSystemControlRules.targetIsCurrent(target, name: "Renamed earbuds",
                            devices: [device()], paired: paired))
        }
        XCTAssertFalse(matches(target, "Renamed earbuds", []))
        XCTAssertFalse(matches(target, "Renamed earbuds", [device(current: false)]))
        XCTAssertFalse(matches(target, "Renamed earbuds", [device(uid: "reused-id")]))
        XCTAssertFalse(matches(target, "Renamed earbuds", [device(id: 43)]))
        XCTAssertFalse(matches(target, "Renamed earbuds", [device(model: "speaker")]))
        XCTAssertFalse(matches(target, "Renamed earbuds", [device(name: "Renamed again")]))
        XCTAssertFalse(matches(target, "Renamed earbuds", [device(), device(id: 43, current: false)]))
        XCTAssertFalse(matches(PanelAudioDeviceID(id: 42, uid: nil), "Renamed earbuds", [device()]))
    }

}
