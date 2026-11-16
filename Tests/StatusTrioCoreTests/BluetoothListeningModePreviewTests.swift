import CoreAudio
import Foundation
import XCTest

@testable import StatusTrioCore

/// The Settings-side preview. Every guarantee here is that the preview looks and
/// behaves like the real row without touching a device: the same three capsules
/// publish for any connected AirPods (regardless of what the HAL would say), a
/// tap animates through the same `.changing` → `.settled` path, and no call ever
/// reaches CoreAudio. Turning preview off returns the row to its fail-closed
/// behaviour on the next refresh — a preview presentation cannot leak into the
/// live surface.
///
/// It reuses the scripted backend and the empty endpoint provider the other
/// listening-mode tests already have, so a preview test that accidentally let a
/// real write through would light up `backend.writeCount`.
@MainActor
final class BluetoothListeningModePreviewTests: XCTestCase {
    private let deviceAddress = "AA:BB:CC:DD:EE:FF"
    private var key: String { BluetoothBatteryReader.normalizedAddress(deviceAddress) }

    private func connectedAirPods() -> BluetoothDevice {
        BluetoothDevice(id: deviceAddress, name: "AirPods Pro", kind: .audio, isConnected: true)
    }

    private func disconnectedAirPods() -> BluetoothDevice {
        BluetoothDevice(id: deviceAddress, name: "AirPods Pro", kind: .audio, isConnected: false)
    }

    private func nonAirPods() -> BluetoothDevice {
        BluetoothDevice(id: deviceAddress, name: "Plain Buds", kind: .audio, isConnected: true)
    }

    /// A controller in preview: real HAL (scripted backend, so writes are counted),
    /// empty endpoint provider (so the non-preview path always publishes nothing),
    /// and a tiny preview settle delay so tests do not sit on the real 400ms.
    private func makePreviewController(
        backend: FakeListeningModeBackend = FakeListeningModeBackend()
    ) -> BluetoothListeningModeController {
        let hal = BluetoothListeningModeHAL(
            backend: backend,
            sleeper: ImmediateListeningModeSleeper(),
            retryAttempts: 1,
            retryDelay: .milliseconds(1)
        )
        let controller = BluetoothListeningModeController(
            hal: hal,
            endpointProvider: EmptyListeningModeEndpointProvider(),
            failureClearDelay: .milliseconds(20),
            previewSettleDelay: .milliseconds(10)
        )
        controller.previewMode = true
        return controller
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: - Presentation

    func testPreviewPublishesThreeCapsulesForAnyConnectedAirPods() {
        let controller = makePreviewController()
        controller.refresh(devices: [connectedAirPods()])

        let presentation = controller.presentations[key]
        XCTAssertEqual(presentation?.availableModes, BluetoothListeningModeController.previewAvailableModes)
        XCTAssertEqual(presentation?.availableModes.count, 3)
        XCTAssertEqual(presentation?.selectedMode, .noiseCancellation)
        XCTAssertEqual(presentation?.isControllable, true)
    }

    func testPreviewIgnoresDisconnectedAndNonAirPods() {
        let controller = makePreviewController()
        controller.refresh(devices: [disconnectedAirPods(), nonAirPods()])
        XCTAssertTrue(controller.presentations.isEmpty, "preview keeps the AirPods-only rule")
    }

    /// Preview bypasses the endpoint provider, so the discovery path never runs.
    /// The whole point is to be able to exercise the row without a device, and the
    /// corollary is that no `lstm`/`lsms` read is issued either — the provider is
    /// the only entry into the HAL from `refresh`, so a zero-call provider proves
    /// the whole HAL stays untouched on this path.
    func testPreviewDiscoveryDoesNotAskTheEndpointProvider() async {
        let provider = CountingEndpointProvider()
        let hal = BluetoothListeningModeHAL(
            backend: FakeListeningModeBackend(),
            sleeper: ImmediateListeningModeSleeper(),
            retryAttempts: 1,
            retryDelay: .milliseconds(1)
        )
        let controller = BluetoothListeningModeController(
            hal: hal,
            endpointProvider: provider,
            failureClearDelay: .milliseconds(20),
            previewSettleDelay: .milliseconds(10)
        )
        controller.previewMode = true
        controller.refresh(devices: [connectedAirPods()])
        await waitUntil { controller.presentations[self.key] != nil }
        XCTAssertEqual(provider.callCount, 0, "preview must skip endpoint discovery")
    }

    func testPreviewSnapshotHonorsVisibleGroups() {
        let suiteName = "AirPodsLayoutShowcase.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { TestUserDefaults.removeSuite(named: suiteName) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let snapshot = ListeningModePreview.systemControlSnapshot(
            localization, spatialSupported: false, conversationSupported: true
        )
        XCTAssertFalse(AirPodsSpatialConversationView.showsSpatial(snapshot))
        XCTAssertTrue(AirPodsSpatialConversationView.showsConversation(snapshot))
    }

    func testDevelopmentLayoutVariantsKeepLiveRowsUntouched() {
        let presentation = BluetoothListeningModePresentation(
            availableModes: [.noiseCancellation, .transparency, .adaptive], selectedMode: .noiseCancellation
        )
        var live = PanelAudioDeviceRow(
            key: .init(id: 42, uid: "AA-BB-CC-DD-EE-FF:output"), name: "Real AirPods",
            symbol: .symbol(name: "airpodspro", variableValue: nil, fallback: nil),
            selected: true, enabled: true, accessibilityLabel: "Real AirPods"
        )
        live.listeningMode = presentation
        live.supportsAirPodsSystemControls = true
        live.airPodsSpatialSupported = true
        live.airPodsConversationSupported = true
        let previews = (0..<3).map { index in
            var row = live
            row = PanelAudioDeviceRow(
                key: .init(id: UInt32(100 + index), uid: "preview-\(index)"), name: "AirPods \(index)",
                symbol: row.symbol, selected: true, enabled: false,
                accessibilityLabel: "AirPods \(index)", listeningMode: presentation,
                isPreview: true, supportsAirPodsSystemControls: true,
                airPodsSpatialSupported: true, airPodsConversationSupported: true
            )
            return row
        }
        let rows = ListeningModePreview.applyingLayoutVariants(to: [live] + previews)
        XCTAssertEqual(rows[0], live)
        XCTAssertNotNil(rows[1].listeningMode)
        XCTAssertTrue(rows[1].airPodsSpatialSupported && rows[1].airPodsConversationSupported)
        XCTAssertNil(rows[2].listeningMode)
        XCTAssertTrue(rows[2].airPodsSpatialSupported && rows[2].airPodsConversationSupported)
        XCTAssertNil(rows[3].listeningMode)
        XCTAssertFalse(rows[3].airPodsSpatialSupported)
        XCTAssertTrue(rows[3].airPodsConversationSupported)
        XCTAssertEqual(Set(rows.map(\.key)).count, rows.count)
    }

    // MARK: - Write path

    /// A tap publishes the in-flight state immediately, and settles onto the tapped
    /// mode after the fixed delay — the same animation the real row produces, with
    /// no CoreAudio write anywhere.
    func testPreviewSetModeWalksTheSameStateMachineWithoutWriting() async {
        let backend = FakeListeningModeBackend()
        let controller = makePreviewController(backend: backend)
        controller.refresh(devices: [connectedAirPods()])

        controller.setMode(.transparency, for: connectedAirPods())

        let busy = controller.presentations[key]
        XCTAssertEqual(busy?.isChanging, true, "preview tap publishes changing(to:)")
        XCTAssertEqual(busy?.isChanging(to: .transparency), true)
        XCTAssertEqual(backend.writeCount, 0, "preview must never hit the HAL write")

        await waitUntil { controller.presentations[self.key]?.selectedMode == .transparency }
        let settled = controller.presentations[key]
        XCTAssertEqual(settled?.selectedMode, .transparency)
        XCTAssertEqual(settled?.isChanging, false)
        XCTAssertEqual(backend.writeCount, 0, "and it still has not written after settling")
    }

    /// Re-tapping the capsule that is already selected turns the preview off, the
    /// same interaction the real row offers.
    func testPreviewRetapOfSelectedModeTurnsItOff() async {
        let controller = makePreviewController()
        controller.refresh(devices: [connectedAirPods()])
        // The default selection is noise cancellation, so re-tapping it starts an
        // Off write that settles with no highlight.
        controller.setMode(.noiseCancellation, for: connectedAirPods())
        XCTAssertEqual(controller.presentations[key]?.isChanging(to: .off), true)

        await waitUntil { controller.presentations[self.key]?.isChanging == false }
        XCTAssertNil(controller.presentations[key]?.selectedMode, "turning off clears the highlight")

        // A stale refresh must not snap the picker back to the default mode.
        controller.refresh(devices: [connectedAirPods()])
        XCTAssertNil(
            controller.presentations[key]?.selectedMode,
            "a turned-off preview stays unhighlighted across refreshes"
        )
    }

    /// Two taps in quick succession: the second is refused because the first is
    /// still in flight. This is the "one write per tap" rule previewed the same way.
    func testPreviewSecondTapWhileChangingIsIgnored() {
        let controller = makePreviewController()
        controller.refresh(devices: [connectedAirPods()])

        controller.setMode(.transparency, for: connectedAirPods())
        controller.setMode(.adaptive, for: connectedAirPods())

        XCTAssertEqual(controller.presentations[key]?.isChanging(to: .transparency), true)
        XCTAssertEqual(controller.presentations[key]?.isChanging(to: .adaptive), false)
    }

    /// The selection persists across refreshes inside a preview session — the panel
    /// can disappear and come back, or the device list can refresh, without the
    /// picker snapping back to the default.
    func testPreviewSelectionPersistsAcrossRefreshes() async {
        let controller = makePreviewController()
        controller.refresh(devices: [connectedAirPods()])
        controller.setMode(.adaptive, for: connectedAirPods())
        await waitUntil { controller.presentations[self.key]?.selectedMode == .adaptive }

        controller.refresh(devices: [connectedAirPods()])
        XCTAssertEqual(controller.presentations[key]?.selectedMode, .adaptive)
    }

    // MARK: - Turn preview off

    /// Turning preview off returns the row to the fail-closed real path: no
    /// endpoint provider hit produces an entry here, so the presentation must
    /// clear. If it did not, the toggle would be a leak.
    func testTurningPreviewOffClearsThePresentationOnNextRefresh() async {
        let controller = makePreviewController()
        controller.refresh(devices: [connectedAirPods()])
        await waitUntil { controller.presentations[self.key] != nil }
        XCTAssertNotNil(controller.presentations[key])

        controller.previewMode = false
        controller.refresh(devices: [connectedAirPods()])
        XCTAssertNil(controller.presentations[key], "the real path must not see preview state")
    }

    /// The preview selection is dropped on the real path so that turning preview
    /// back on later starts from the default. Nothing a test session picked in
    /// preview bleeds forward.
    func testRealRefreshDropsPreviewSelection() async {
        let controller = makePreviewController()
        controller.refresh(devices: [connectedAirPods()])
        controller.setMode(.adaptive, for: connectedAirPods())
        await waitUntil { controller.presentations[self.key]?.selectedMode == .adaptive }

        controller.previewMode = false
        controller.refresh(devices: [connectedAirPods()])

        controller.previewMode = true
        controller.refresh(devices: [connectedAirPods()])
        XCTAssertEqual(controller.presentations[key]?.selectedMode, .noiseCancellation)
    }
}

/// Endpoint provider that returns nothing and counts the calls it received, so
/// the preview-bypass claim is measured on discovery specifically.
private final class CountingEndpointProvider: CoreAudioBluetoothEndpointProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _callCount = 0

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _callCount
    }

    func discoverEndpoints(using hal: BluetoothListeningModeHAL) -> [BluetoothListeningModeEndpoint] {
        lock.lock(); _callCount += 1; lock.unlock()
        return []
    }
}
