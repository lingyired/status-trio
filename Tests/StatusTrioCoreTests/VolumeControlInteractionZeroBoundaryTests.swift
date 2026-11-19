import XCTest
@testable import StatusTrioCore

final class VolumeControlInteractionZeroBoundaryTests: XCTestCase {
    private let identity = VolumeControlInteractionIdentity(
        output: PanelAudioDeviceID(id: 1, uid: "output-a"),
        configuration: .default
    )

    private func makeInteraction(
        onSet: @escaping (Double) -> Void,
        onFinish: @escaping () -> Void = {}
    ) -> VolumeControlInteraction {
        VolumeControlInteraction(setVolume: onSet, finishVolume: onFinish)
    }

    func testSystemSyncNeverWritesVolume() {
        var writes: [Double] = []
        var interaction = makeInteraction(onSet: { writes.append($0) })

        interaction.receiveSystemState(identity: identity, scalar: 0, canAdjust: true)

        XCTAssertTrue(writes.isEmpty)
    }

    func testClickingFarLeftAtZeroStillTriggersPreciseZeroWrite() {
        var writes: [Double] = []
        var interaction = makeInteraction(onSet: { writes.append($0) })
        interaction.receiveSystemState(identity: identity, scalar: 0, canAdjust: true)

        interaction.setSliderValue(0, identity: identity, canAdjust: true)

        XCTAssertEqual(writes, [0])
    }

    func testRepeatedZeroDragEventsWithinOneGestureAreDeduplicated() {
        var writes: [Double] = []
        var interaction = makeInteraction(onSet: { writes.append($0) })
        interaction.receiveSystemState(identity: identity, scalar: 0, canAdjust: true)

        interaction.beginEditing()
        interaction.setSliderValue(0, identity: identity, canAdjust: true)
        interaction.setSliderValue(0, identity: identity, canAdjust: true)
        interaction.setSliderValue(0, identity: identity, canAdjust: true)

        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(writes, [0])
    }

    func testNextGestureCanZeroAgain() {
        var writes: [Double] = []
        var interaction = makeInteraction(onSet: { writes.append($0) })
        interaction.receiveSystemState(identity: identity, scalar: 0, canAdjust: true)

        interaction.beginEditing()
        interaction.setSliderValue(0, identity: identity, canAdjust: true)
        interaction.endEditing(identity: identity)

        interaction.beginEditing()
        interaction.setSliderValue(0, identity: identity, canAdjust: true)

        XCTAssertEqual(writes, [0, 0])
    }

    func testDraggingToZeroFromNonZeroEmitsZeroOnce() {
        var writes: [Double] = []
        var interaction = makeInteraction(onSet: { writes.append($0) })
        interaction.receiveSystemState(identity: identity, scalar: 0.3, canAdjust: true)

        interaction.beginEditing()
        interaction.setSliderValue(0.1, identity: identity, canAdjust: true)
        interaction.setSliderValue(0, identity: identity, canAdjust: true)
        interaction.setSliderValue(0, identity: identity, canAdjust: true)

        XCTAssertEqual(writes, [0.1, 0])
    }

    func testRaiseThenZeroAgainEmitsSecondZero() {
        var writes: [Double] = []
        var interaction = makeInteraction(onSet: { writes.append($0) })
        interaction.receiveSystemState(identity: identity, scalar: 0, canAdjust: true)

        interaction.beginEditing()
        interaction.setSliderValue(0, identity: identity, canAdjust: true)
        interaction.setSliderValue(0.2, identity: identity, canAdjust: true)
        interaction.setSliderValue(0, identity: identity, canAdjust: true)

        XCTAssertEqual(writes, [0, 0.2, 0])
    }
}
