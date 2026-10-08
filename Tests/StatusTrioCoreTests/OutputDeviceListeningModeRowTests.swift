import AppKit
import SwiftUI
import XCTest

@testable import StatusTrioCore

/// The AirPods listening-mode control's interaction shape *on the audio output
/// row*, measured the way the rest of the panel layout tests measure: the AppKit
/// views SwiftUI actually hosts (one focus-ring host per `Button`, one
/// `NSProgressIndicator` per animated busy mark). The accessibility tree is empty
/// in this `NSHostingView` harness, so the "capsules stay individually reachable"
/// requirement is proved by the capsules rendering as *separate* buttons, not
/// folded into the row's selection button — a combined element would collapse them
/// to one focus target and draw as one control.
///
/// It also locks the fail-closed rule at the view boundary: a presentation the
/// control is not certain about (fewer than two modes, or none handed in at all)
/// must render the ordinary one-button output row, never a half control.
@MainActor
final class OutputDeviceListeningModeRowTests: XCTestCase {
    /// A current Bluetooth output — the only kind of output row the control ever
    /// attaches to, because only the active AirPods can switch its mode.
    private func currentAirPodsOutput() -> AudioOutputDevice {
        AudioOutputDevice(
            id: 42,
            name: "AirPods Pro",
            isCurrent: true,
            transport: .bluetooth
        )
    }

    private let threeModes: [BluetoothListeningMode] = [.noiseCancellation, .transparency, .adaptive]

    /// A controllable row is the selection button plus one capsule per mode. Three
    /// modes must render four focus-ring controls — proof each capsule is its own
    /// button the keyboard and VoiceOver can land on, not ink inside the primary
    /// button.
    func testControllableRowRendersEachModeAsItsOwnButton() async throws {
        let row = try await render(
            device: currentAirPodsOutput(),
            listeningMode: BluetoothListeningModePresentation(
                availableModes: threeModes,
                selectedMode: .noiseCancellation
            )
        )
        XCTAssertEqual(row.controls.count, 4, "selection button + three capsules")
    }

    /// Fail-closed: a device that supports only one mode has nothing to switch, so
    /// the row must fall back to the ordinary single-button row — no capsule group,
    /// no half control.
    func testSingleModePresentationDrawsNoControl() async throws {
        let row = try await render(
            device: currentAirPodsOutput(),
            listeningMode: BluetoothListeningModePresentation(
                availableModes: [.noiseCancellation],
                selectedMode: .noiseCancellation
            )
        )
        XCTAssertEqual(row.controls.count, 1, "only the selection button; a lone mode is not a switch")
    }

    /// Fail-closed for absence: an output row the controller resolved no control for
    /// (any ordinary or non-current device) is exactly one button. This is the shape
    /// every non-AirPods output keeps.
    func testNilPresentationDrawsNoControl() async throws {
        let row = try await render(
            device: currentAirPodsOutput(),
            listeningMode: nil
        )
        XCTAssertEqual(row.controls.count, 1, "an ordinary output row is a single button")
    }

    /// The in-flight capsule stays its own focusable button. Whether it marks itself
    /// with a spinner or a static dot depends on `@Environment(\.accessibilityReduceMotion)`
    /// — `busyMark` draws a `ProgressView` normally and a static `Circle` under Reduce
    /// Motion — and that key is read-only, so this `NSHostingView` harness inherits
    /// whatever the host has set (CI runners enable Reduce Motion, so no
    /// `NSProgressIndicator` appears there). The marker choice is therefore not a
    /// stable render assertion; what is stable, and what this test exists to lock, is
    /// that a busy capsule is still a separate button the keyboard and VoiceOver can
    /// land on rather than ink folded into another control.
    func testInFlightCapsuleRemainsItsOwnButton() async throws {
        let row = try await render(
            device: currentAirPodsOutput(),
            listeningMode: BluetoothListeningModePresentation(
                availableModes: threeModes,
                selectedMode: .noiseCancellation
            ).changing(to: .transparency)
        )
        XCTAssertEqual(row.controls.count, 4, "the busy capsule is still its own button")
    }

    /// A settled (idle) controllable row draws no spinner at all — the busy mark only
    /// appears while a change is in flight. Guards against the capsules accidentally
    /// carrying a persistent progress indicator.
    func testSettledRowDrawsNoSpinner() async throws {
        let row = try await render(
            device: currentAirPodsOutput(),
            listeningMode: BluetoothListeningModePresentation(
                availableModes: threeModes,
                selectedMode: .noiseCancellation
            )
        )
        XCTAssertEqual(row.spinners, 0, "an idle row has nothing in flight")
    }

    // MARK: - Rendering

    private struct RenderedRow {
        let controls: [NSRect]
        let spinners: Int
    }

    private func render(
        device: AudioOutputDevice,
        listeningMode: BluetoothListeningModePresentation?
    ) async throws -> RenderedRow {
        let suite = "StatusTrioCoreTests.OutputListeningModeRow.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        localization.setPreference(.language(.english))

        let rowState = PanelAudioDeviceRow(
            key: PanelAudioDeviceID(id: device.id, uid: device.uid),
            name: device.name ?? "AirPods Pro",
            symbol: AudioPanelMapper.iconSource(for: device),
            selected: device.isCurrent,
            enabled: true,
            accessibilityLabel: device.name ?? "AirPods Pro",
            listeningModeAddress: listeningMode == nil ? nil : device.uid,
            listeningMode: listeningMode
        )
        let row = OutputDeviceRow(
            state: rowState,
            onSelect: {},
            onSelectListeningMode: { _ in }
        )
        .padding(14)
        .frame(width: 330)
        .background(Color(white: 0.96))
        .environmentObject(localization)
        .environment(\.colorScheme, .light)

        let hosting = NSHostingView(rootView: row)
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(60))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()

        var controls: [NSRect] = []
        var spinners = 0
        var pending = hosting.subviews
        while let subview = pending.popLast() {
            if String(describing: type(of: subview)).contains("FocusRing") {
                controls.append(subview.convert(subview.bounds, to: hosting))
            }
            if subview is NSProgressIndicator {
                spinners += 1
            }
            pending.append(contentsOf: subview.subviews)
        }
        return RenderedRow(controls: controls, spinners: spinners)
    }
}
