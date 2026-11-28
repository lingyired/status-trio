import XCTest
@testable import StatusTrioCore

final class MenuBarHoverPanelStateMachineTests: XCTestCase {
    func testHoverEnterSchedulesOpen() {
        let machine = MenuBarHoverPanelStateMachine()
        let a = UUID()
        guard case .scheduleOpen(let id, _) = machine.handle(.hoverEnter(a)) else {
            return XCTFail("expected scheduleOpen")
        }
        XCTAssertEqual(id, a)
    }

    func testHoverExitBeforeOpenCancels() {
        let machine = MenuBarHoverPanelStateMachine()
        let a = UUID()
        guard case .scheduleOpen(_, let openGen) = machine.handle(.hoverEnter(a)) else {
            return XCTFail("expected scheduleOpen")
        }
        guard case .scheduleClose = machine.handle(.hoverExit(a)) else {
            return XCTFail("expected scheduleClose")
        }
        XCTAssertEqual(machine.fire(generation: openGen, .present(a)), .none)
    }

    func testStaleCloseDoesNotCloseNewInstance() {
        let machine = MenuBarHoverPanelStateMachine()
        let a = UUID()
        let b = UUID()
        _ = machine.handle(.hoverEnter(a))
        _ = machine.handle(.openConfirmed(a))
        guard case .scheduleClose(_, let closeGen) = machine.handle(.hoverExit(a)) else {
            return XCTFail("expected scheduleClose")
        }
        _ = machine.handle(.hoverEnter(b))
        XCTAssertEqual(machine.fire(generation: closeGen, .close), .none)
    }

    func testClickOnHoverPanelPins() {
        let machine = MenuBarHoverPanelStateMachine()
        let a = UUID()
        _ = machine.handle(.hoverEnter(a))
        _ = machine.handle(.openConfirmed(a))
        XCTAssertEqual(machine.handle(.click(a)), .pin)
        XCTAssertTrue(machine.state.isOpen)
        XCTAssertEqual(machine.state.sourceInstanceID, a)
    }

    func testOpenOnlyOnePanelSwitchesSource() {
        let machine = MenuBarHoverPanelStateMachine()
        let a = UUID()
        let b = UUID()
        _ = machine.handle(.hoverEnter(a))
        _ = machine.handle(.openConfirmed(a))
        _ = machine.handle(.hoverEnter(b))
        _ = machine.handle(.openConfirmed(b))
        XCTAssertEqual(machine.state.sourceInstanceID, b)
        XCTAssertTrue(machine.state.isOpen)
    }
}
