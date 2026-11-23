import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// The volume panel resizes the popover window from the content's measured
/// height. If the expanded AirPods section reports a different height on every
/// layout pass the panel keeps resizing and the expansion visibly shakes, so
/// the measured height must settle after the first pass.
@MainActor
final class AirPodsInlineControlsSizingTests: XCTestCase {
    private func makeLocalization() -> Localization {
        let suite = "AirPodsInlineControlsSizingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { TestUserDefaults.removeSuite(named: suite) }
        return Localization(defaults: defaults, preferredLanguages: ["en"])
    }

    func testExpandedInlineControlsReportAStableHeight() {
        let localization = makeLocalization()
        let model = AirPodsSystemControlsModel(
            deviceID: PanelAudioDeviceID(id: 42, uid: "AA-BB-CC-DD-EE-FF:output"),
            deviceName: "AirPods Pro",
            preview: ListeningModePreview.systemControlSnapshot(localization)
        )
        let view = AirPodsSystemControlsView(
            model: model,
            listeningMode: nil,
            onSelectListeningMode: { _ in }
        )
        .environmentObject(localization)

        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 900)

        var heights: [CGFloat] = []
        for _ in 0..<6 {
            host.layoutSubtreeIfNeeded()
            heights.append(host.fittingSize.height)
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }

        let settled = heights.dropFirst()
        XCTAssertGreaterThan(heights[0], 0)
        XCTAssertTrue(
            settled.allSatisfy { abs($0 - heights[0]) < 0.5 },
            "Height must settle immediately; got \(heights)"
        )
    }
}
