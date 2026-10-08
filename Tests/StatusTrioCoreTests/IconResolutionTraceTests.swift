import XCTest
@testable import StatusTrioCore

final class IconResolutionTraceTests: XCTestCase {
    func testTraceContainsOnlySourceAndFailureMetadata() {
        let trace = SlotResolutionTrace(
            selectedSourceID: CenterSource.network.rawValue,
            role: .fallback,
            primaryFailure: .disconnected,
            reason: .fallback(.disconnected)
        )

        XCTAssertEqual(trace.selectedSourceID, "network")
        XCTAssertEqual(trace.role, .fallback)
        XCTAssertEqual(trace.primaryFailure, .disconnected)
        XCTAssertEqual(trace.reason, .fallback(.disconnected))
    }

    func testSceneEqualityDoesNotIncludeTrace() {
        let scene = IconSceneState(center: .symbol(IconSymbolState(
            source: .symbol(name: "wifi", variableValue: 1, fallback: nil), color: .primary, scale: 1
        )))
        let primary = IconResolutionOutput(scene: scene, trace: .empty)
        var alternateTrace = IconResolutionTrace.empty
        alternateTrace.center = SlotResolutionTrace(
            selectedSourceID: CenterSource.network.rawValue, role: .fallback,
            primaryFailure: .disconnected, reason: .fallback(.disconnected)
        )
        let fallback = IconResolutionOutput(scene: scene, trace: alternateTrace)

        XCTAssertEqual(primary.scene, fallback.scene)
        XCTAssertNotEqual(primary.trace, fallback.trace)
    }
}
