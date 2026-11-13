import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// A supported AirPods model must keep the Spatial Audio / Conversation
/// Awareness group on screen even when its live read comes back empty (no
/// active media client, or a failed HAL read). It renders a single disabled
/// "unavailable" capsule instead of disappearing, matching the native Sound
/// menu and the original direct-control design.
@MainActor
final class AirPodsSpatialUnavailableTests: XCTestCase {
    private func makeLocalization() -> Localization {
        let suite = "AirPodsSpatialUnavailableTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { TestUserDefaults.removeSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(.english))
        return localization
    }

    private func makeModel(_ snapshot: AirPodsSystemSnapshot) -> AirPodsSystemControlsModel {
        AirPodsSystemControlsModel(
            deviceID: PanelAudioDeviceID(id: 42, uid: "AA-BB-CC-DD-EE-FF:output"),
            deviceName: "AirPods Pro",
            preview: snapshot
        )
    }

    private struct Rendered {
        let height: CGFloat
        let controls: Int
    }

    private func render(_ snapshot: AirPodsSystemSnapshot, width: CGFloat = 300) -> Rendered {
        let localization = makeLocalization()
        let model = makeModel(snapshot)
        let view = AirPodsSpatialConversationView(model: model)
            .environmentObject(localization)
            .frame(width: width)
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()

        var controls = 0
        var pending = hosting.subviews
        while let subview = pending.popLast() {
            if String(describing: type(of: subview)).contains("FocusRing") { controls += 1 }
            pending.append(contentsOf: subview.subviews)
        }
        return Rendered(height: hosting.fittingSize.height, controls: controls)
    }

    func testSupportedSpatialGroupStaysVisibleAsDisabledUnavailableWhenReadIsEmpty() {
        let snapshot = AirPodsSystemSnapshot(
            spatial: [],
            spatialLoaded: true,
            supportsSpatial: true,
            supportsConversation: false
        )
        XCTAssertTrue(AirPodsSpatialConversationView.showsSpatial(snapshot))

        let rendered = render(snapshot)
        XCTAssertGreaterThan(rendered.height, 0, "the group must still occupy space")
        XCTAssertEqual(rendered.controls, 0, "the unavailable placeholder must not be clickable")
    }

    func testUnsupportedModelStillHidesSpatialGroup() {
        let snapshot = AirPodsSystemSnapshot(
            spatial: [],
            spatialLoaded: true,
            supportsSpatial: false,
            supportsConversation: false
        )
        XCTAssertFalse(AirPodsSpatialConversationView.showsSpatial(snapshot))
        XCTAssertEqual(render(snapshot).height, 0)
    }

    func testReadableSpatialOptionsRemainClickable() {
        let options = Self.threeSpatialOptions
        let snapshot = AirPodsSystemSnapshot(
            spatial: options,
            spatialLoaded: true,
            supportsSpatial: true,
            supportsConversation: false
        )
        XCTAssertEqual(render(snapshot).controls, options.count)
    }

    /// The disclosure must decide one row vs. two from the full three-option
    /// width, not from whatever stand-in is showing. Otherwise the layout jumps
    /// rows the moment playback makes the options readable (or stops again).
    func testUnavailableAndAvailableReserveTheSameRowLayout() {
        let conversation = [
            AirPodsSystemOption(title: "Off", selected: false, symbol: "person.wave.2.fill", dimWaves: true),
            AirPodsSystemOption(title: "On", selected: true, symbol: "person.wave.2.fill")
        ]
        let unavailable = AirPodsSystemSnapshot(
            conversation: conversation, spatial: [], conversationLoaded: true, spatialLoaded: true,
            supportsSpatial: true, supportsConversation: true
        )
        let available = AirPodsSystemSnapshot(
            conversation: conversation, spatial: Self.threeSpatialOptions,
            conversationLoaded: true, spatialLoaded: true,
            supportsSpatial: true, supportsConversation: true
        )
        let loading = AirPodsSystemSnapshot(
            conversation: conversation, spatial: [], conversationLoaded: true, spatialLoaded: false,
            supportsSpatial: true, supportsConversation: true
        )

        for width in [240.0, 360.0] as [CGFloat] {
            let availableHeight = render(available, width: width).height
            XCTAssertEqual(render(unavailable, width: width).height, availableHeight, accuracy: 0.5,
                           "unavailable must keep the available layout at width \(width)")
            XCTAssertEqual(render(loading, width: width).height, availableHeight, accuracy: 0.5,
                           "loading must keep the available layout at width \(width)")
        }
    }

    private static let threeSpatialOptions = [
        AirPodsSystemOption(title: "Off", selected: false, symbol: "person.spatialaudio.stereo.fill", dimWaves: true),
        AirPodsSystemOption(title: "Fixed", selected: true, symbol: "person.spatialaudio.stereo.fill"),
        AirPodsSystemOption(title: "Head Tracked", selected: false, symbol: "spatialize-stereo-head-tracked")
    ]
}
