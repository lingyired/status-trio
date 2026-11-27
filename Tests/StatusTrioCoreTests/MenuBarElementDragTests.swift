import XCTest
@testable import StatusTrioCore

final class MenuBarElementDragTests: XCTestCase {
    private func instance(layout: MenuBarLayoutMode = .doubleLine) -> MenuBarInstance {
        let top = MenuBarElement(content: .text("A"))
        let top2 = MenuBarElement(content: .metric(.cpuUsage))
        let bottom = MenuBarElement(content: .metric(.gpuUsage))
        return MenuBarInstance(
            layoutMode: layout,
            top: MenuBarLine(elements: [top, top2]),
            bottom: MenuBarLine(elements: [bottom])
        )
    }

    private func contents(_ line: MenuBarLine?) -> [MenuBarElementContent] { line?.elements.map(\.content) ?? [] }

    func testPaletteInsertCreatesNewElement() {
        var inst = instance()
        let payload = MenuBarElementDragPayload(source: .palette(.metric(.memoryUsage)))
        let changed = MenuBarElementMutations.apply(
            payload: payload,
            to: &inst,
            target: .line(instanceID: inst.id, slot: .top, index: 1)
        )
        XCTAssertTrue(changed)
        XCTAssertEqual(contents(inst.top), [.text("A"), .metric(.memoryUsage), .metric(.cpuUsage)])
    }

    func testMoveWithinLineReorders() {
        var inst = instance()
        let id = inst.top!.elements[1].id
        let payload = MenuBarElementDragPayload(source: .placed(instanceID: inst.id, slot: .top, elementID: id))
        let changed = MenuBarElementMutations.apply(
            payload: payload,
            to: &inst,
            target: .line(instanceID: inst.id, slot: .top, index: 0)
        )
        XCTAssertTrue(changed)
        XCTAssertEqual(contents(inst.top), [.metric(.cpuUsage), .text("A")])
    }

    func testSamePositionIsNoOp() {
        var inst = instance()
        let id = inst.top!.elements[0].id
        let payload = MenuBarElementDragPayload(source: .placed(instanceID: inst.id, slot: .top, elementID: id))
        XCTAssertFalse(MenuBarElementMutations.apply(payload: payload, to: &inst, target: .line(instanceID: inst.id, slot: .top, index: 0)))
        XCTAssertFalse(MenuBarElementMutations.apply(payload: payload, to: &inst, target: .line(instanceID: inst.id, slot: .top, index: 1)))
    }

    func testCrossRowMove() {
        var inst = instance()
        let id = inst.top!.elements[1].id
        let payload = MenuBarElementDragPayload(source: .placed(instanceID: inst.id, slot: .top, elementID: id))
        let changed = MenuBarElementMutations.apply(
            payload: payload,
            to: &inst,
            target: .line(instanceID: inst.id, slot: .bottom, index: 0)
        )
        XCTAssertTrue(changed)
        XCTAssertEqual(contents(inst.top), [.text("A")])
        XCTAssertEqual(contents(inst.bottom), [.metric(.cpuUsage), .metric(.gpuUsage)])
    }

    func testSingleLineRejectsBottomDrop() {
        var inst = instance(layout: .singleLine)
        let payload = MenuBarElementDragPayload(source: .palette(.text("X")))
        XCTAssertFalse(MenuBarElementMutations.apply(
            payload: payload, to: &inst, target: .line(instanceID: inst.id, slot: .bottom, index: 0)
        ))
    }

    func testStaleSourceRejected() {
        var inst = instance()
        let payload = MenuBarElementDragPayload(source: .placed(instanceID: inst.id, slot: .top, elementID: UUID()))
        XCTAssertFalse(MenuBarElementMutations.apply(
            payload: payload, to: &inst, target: .line(instanceID: inst.id, slot: .top, index: 0)
        ))
    }

    func testWrongInstanceRejected() {
        var inst = instance()
        let payload = MenuBarElementDragPayload(source: .placed(instanceID: UUID(), slot: .top, elementID: inst.top!.elements[0].id))
        XCTAssertFalse(MenuBarElementMutations.apply(
            payload: payload, to: &inst, target: .line(instanceID: inst.id, slot: .top, index: 0)
        ))
    }
}
