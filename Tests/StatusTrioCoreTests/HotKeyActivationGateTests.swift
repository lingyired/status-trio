import XCTest
@testable import StatusTrioCore

final class HotKeyActivationGateTests: XCTestCase {
    func testRepeatedPressForOneHotKeyActivatesOnlyOnceUntilRelease() {
        var gate = HotKeyActivationGate()

        XCTAssertTrue(gate.shouldActivate(hotKeyID: 7))
        XCTAssertFalse(gate.shouldActivate(hotKeyID: 7))
        XCTAssertFalse(gate.shouldActivate(hotKeyID: 7))

        gate.didRelease(hotKeyID: 7)
        XCTAssertTrue(gate.shouldActivate(hotKeyID: 7))
    }

    func testIndependentHotKeysTrackTheirOwnReleaseState() {
        var gate = HotKeyActivationGate()

        XCTAssertTrue(gate.shouldActivate(hotKeyID: 1))
        XCTAssertTrue(gate.shouldActivate(hotKeyID: 2))
        XCTAssertFalse(gate.shouldActivate(hotKeyID: 1))

        gate.reset()
        XCTAssertTrue(gate.shouldActivate(hotKeyID: 1))
    }

    func testObsoleteHotKeyDoesNotEnterThePressedSet() {
        var gate = HotKeyActivationGate()

        XCTAssertFalse(
            gate.shouldActivate(hotKeyID: 9, isRegistered: false)
        )
        XCTAssertTrue(
            gate.shouldActivate(hotKeyID: 9, isRegistered: true)
        )
    }
}
