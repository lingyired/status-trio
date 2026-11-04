import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class WiFiPowerSummaryTests: XCTestCase {
    // MARK: - Settings persistence

    func testWiFiPowerControlDefaultsOnAndPersists() {
        let suite = makeDefaultsSuite()
        defer { clear(suite) }

        let first = SettingsStore(defaults: suite.defaults)
        XCTAssertTrue(first.showsWiFiPowerControl, "the control is shown by default")

        first.showsWiFiPowerControl = false

        let second = SettingsStore(defaults: suite.defaults)
        XCTAssertFalse(second.showsWiFiPowerControl, "the choice must survive a new store")
    }

    // MARK: - Visibility

    func testControlIsHiddenWithoutWiFiHardware() {
        XCTAssertFalse(WiFiPowerControlVisibility.showsSettingsControl(state: .unavailable))
        XCTAssertFalse(
            WiFiPowerControlVisibility.showsSummaryToggle(state: .unavailable, isEnabled: true)
        )
    }

    func testControlIsShownWheneverTheRadioExists() {
        for state: WiFiState in [.connected, .notAssociated, .off, .noInternet, .hotspot, .temporary, .shared] {
            XCTAssertTrue(
                WiFiPowerControlVisibility.showsSettingsControl(state: state),
                "\(state) must offer the Settings control"
            )
            XCTAssertTrue(
                WiFiPowerControlVisibility.showsSummaryToggle(state: state, isEnabled: true),
                "\(state) must offer the summary control"
            )
            XCTAssertFalse(
                WiFiPowerControlVisibility.showsSummaryToggle(state: state, isEnabled: false),
                "the user's off switch must hide the control for \(state)"
            )
        }
    }

    func testPowerStateFollowsTheWifiState() {
        XCTAssertFalse(WiFiPowerControlVisibility.isRadioOn(state: .off))
        for state: WiFiState in [.connected, .notAssociated, .noInternet, .hotspot, .temporary, .shared] {
            XCTAssertTrue(WiFiPowerControlVisibility.isRadioOn(state: state), "\(state) is on")
        }
    }

    // MARK: - Toggle decision

    func testTurningOffAsksOnlyWhileANetworkIsAssociated() {
        XCTAssertTrue(WiFiPowerTogglePolicy.requiresConfirmation(for: .connected))
        XCTAssertTrue(WiFiPowerTogglePolicy.requiresConfirmation(for: .hotspot))
        for state: WiFiState in [.notAssociated, .off, .noInternet, .temporary, .shared, .unavailable] {
            XCTAssertFalse(
                WiFiPowerTogglePolicy.requiresConfirmation(for: state),
                "\(state) must turn off without asking"
            )
        }
    }

    func testDecisionAsksBeforeTurningOffWhenConnectedOrHotspot() {
        for state: WiFiState in [.connected, .hotspot] {
            XCTAssertEqual(
                WiFiPowerTogglePolicy.decision(
                    isOn: true,
                    requiresConfirmation: WiFiPowerTogglePolicy.requiresConfirmation(for: state)
                ),
                .confirmOff,
                "\(state) must confirm before turning off"
            )
            XCTAssertEqual(
                WiFiPowerTogglePolicy.decision(
                    isOn: false,
                    requiresConfirmation: WiFiPowerTogglePolicy.requiresConfirmation(for: state)
                ),
                .set(true),
                "\(state) turns on without asking"
            )
        }
    }

    func testDecisionTurnsOffDirectlyWhenNotAssociated() {
        XCTAssertEqual(
            WiFiPowerTogglePolicy.decision(
                isOn: true,
                requiresConfirmation: WiFiPowerTogglePolicy.requiresConfirmation(for: .notAssociated)
            ),
            .set(false)
        )
        XCTAssertEqual(
            WiFiPowerTogglePolicy.decision(
                isOn: false,
                requiresConfirmation: false
            ),
            .set(true)
        )
    }

    // MARK: - Accessibility

    func testAccessibilityAnnouncesTheActionAndTheState() throws {
        let localization = try makeLocalization()
        XCTAssertEqual(
            WiFiPowerTogglePolicy.accessibilityLabel(isOn: true, localization: localization),
            "Turn Wi-Fi off"
        )
        XCTAssertEqual(
            WiFiPowerTogglePolicy.accessibilityLabel(isOn: false, localization: localization),
            "Turn Wi-Fi on"
        )
        XCTAssertEqual(
            WiFiPowerTogglePolicy.accessibilityValue(isOn: true, localization: localization),
            "On"
        )
        XCTAssertEqual(
            WiFiPowerTogglePolicy.accessibilityValue(isOn: false, localization: localization),
            "Off"
        )
    }

    // MARK: - Summary row rendering

    func testWiFiRowShowsPowerControlAndWiredRowDoesNot() throws {
        let wifi = try render(
            makeView(intent: .wifiDetails, showsWiFiPowerControl: true, wifiPowerIsOn: true)
        )
        let wifiGlyphs = wifi.trailingGlyphRects(count: 3, minimumX: 150)
        XCTAssertEqual(wifiGlyphs.count, 3, "Wi-Fi row must draw power, chevron and Settings")

        let wired = try render(
            makeView(intent: .wiredDetails, showsWiFiPowerControl: true, wifiPowerIsOn: true)
        )
        let wiredGlyphs = wired.trailingGlyphRects(count: 3, minimumX: 150)
        XCTAssertEqual(wiredGlyphs.count, 2, "the wired row must not draw a Wi-Fi power control")
    }

    func testPowerControlRendersForOnOffAndUnavailable() throws {
        // Short row content so the only trailing ink is the control set itself.
        let on = try render(
            makeView(
                intent: .wifiDetails, showsWiFiPowerControl: true, wifiPowerIsOn: true,
                title: "A", subtitle: " "
            )
        )
        XCTAssertEqual(on.trailingGlyphRects(count: 3, minimumX: 150).count, 3)

        let off = try render(
            makeView(
                intent: .wifiDetails, showsWiFiPowerControl: true, wifiPowerIsOn: false,
                title: "A", subtitle: " "
            )
        )
        XCTAssertEqual(off.trailingGlyphRects(count: 3, minimumX: 150).count, 3)

        // No Wi-Fi hardware: the wiring passes showsWiFiPowerControl == false.
        let unavailable = try render(
            makeView(
                intent: .wifiDetails, showsWiFiPowerControl: false, wifiPowerIsOn: false,
                title: "A", subtitle: " "
            )
        )
        XCTAssertEqual(
            unavailable.trailingGlyphRects(count: 3, minimumX: 150).count,
            2,
            "unavailable Wi-Fi must not draw the power control"
        )
    }

    /// The summary row is fixed at 330pt. Adding the control must not push the
    /// title/subtitle into a second line or overflow the row.
    func testWiFiRowWithPowerControlStaysSingleLineAt330() throws {
        let probe = try render(
            makeView(
                intent: .wifiDetails,
                showsWiFiPowerControl: true,
                wifiPowerIsOn: true,
                title: "An Extraordinarily Long Wi-Fi Network Name That Would Wrap"
            )
        )
        let height = CGFloat(probe.bitmap.pixelsHigh) / probe.scale
        XCTAssertLessThanOrEqual(height, 64, "the 330pt row must remain a single line")

        let glyphs = probe.trailingGlyphRects(count: 3, minimumX: 150)
        XCTAssertEqual(glyphs.count, 3)
        let rightmost = glyphs.map(\.maxX).max() ?? 0
        XCTAssertLessThanOrEqual(rightmost, 330, "the trailing controls must stay inside 330pt")
    }

    // MARK: - Store action

    func testQuickPowerActionReachesTheRadioWithoutAnOpenDetailPage() async {
        let scanner = FakeWiFiPowerScanner()
        let controller = WiFiNetworkController(scanWorker: scanner)
        let monitor = CountingWiFiMonitor()
        let store = makeStore(
            scanner: scanner,
            controller: controller,
            wifiMonitor: monitor,
            wifiState: .connected
        )

        XCTAssertFalse(controller.isActive, "the detail page is closed")
        store.setWiFiPower(false)

        await waitUntil { scanner.powerValues == [false] }
        XCTAssertEqual(scanner.powerValues, [false], "the quick action must reach the radio")

        await waitUntil { monitor.refreshCount >= 1 }
        XCTAssertGreaterThanOrEqual(
            monitor.refreshCount,
            1,
            "the snapshot must be refreshed instead of waiting for the poll"
        )
        XCTAssertFalse(store.wifiPowerIsChanging)
        XCTAssertFalse(store.wifiPowerFailed)
    }

    func testFailedPowerActionIsReported() async {
        let scanner = FakeWiFiPowerScanner()
        scanner.powerSucceeds = false
        let controller = WiFiNetworkController(scanWorker: scanner)
        let monitor = CountingWiFiMonitor()
        let store = makeStore(
            scanner: scanner,
            controller: controller,
            wifiMonitor: monitor,
            wifiState: .connected
        )

        store.setWiFiPower(false)
        await waitUntil { !store.wifiPowerIsChanging && scanner.powerValues.count == 1 }

        XCTAssertTrue(store.wifiPowerFailed, "a rejected write must be visible")
    }

    func testFailedPowerWriteClearsWhenTheSnapshotMatchesTheRequestedState() async {
        let fixture = makeStartedStore(wifiState: .connected, powerSucceeds: false)
        let store = fixture.store
        store.setWiFiPower(false)
        await waitUntil { !store.wifiPowerIsChanging && fixture.scanner.powerValues.count == 1 }
        XCTAssertTrue(store.wifiPowerFailed)

        // The radio reaching the requested off state clears the message.
        fixture.monitor.send(WiFiStatus(state: .off, rssi: nil))
        await waitUntil { !store.wifiPowerFailed }
        XCTAssertFalse(store.wifiPowerFailed, "a matching snapshot must clear the stale failure")
    }

    func testFailedPowerWriteClearsWhenTurningOnReachesConnected() async {
        let fixture = makeStartedStore(wifiState: .off, powerSucceeds: false)
        let store = fixture.store
        store.setWiFiPower(true)
        await waitUntil { !store.wifiPowerIsChanging && fixture.scanner.powerValues.count == 1 }
        XCTAssertTrue(store.wifiPowerFailed)

        fixture.monitor.send(WiFiStatus(state: .connected, rssi: -50))
        await waitUntil { !store.wifiPowerFailed }
        XCTAssertFalse(store.wifiPowerFailed)
    }

    func testFailedPowerWriteStaysWhileTheSnapshotDisagrees() async {
        let fixture = makeStartedStore(wifiState: .connected, powerSucceeds: false)
        let store = fixture.store
        store.setWiFiPower(false)
        await waitUntil { !store.wifiPowerIsChanging && fixture.scanner.powerValues.count == 1 }
        XCTAssertTrue(store.wifiPowerFailed)

        fixture.monitor.send(WiFiStatus(state: .connected, rssi: -55))
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertTrue(store.wifiPowerFailed, "a snapshot that still reports on keeps the failure")
    }

    func testFailedPowerWriteStaysWhenTheInterfaceDisappears() async {
        let fixture = makeStartedStore(wifiState: .connected, powerSucceeds: false)
        let store = fixture.store
        store.setWiFiPower(false)
        await waitUntil { !store.wifiPowerIsChanging && fixture.scanner.powerValues.count == 1 }

        fixture.monitor.send(WiFiStatus(state: .unavailable, rssi: nil))
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertTrue(store.wifiPowerFailed, "an unavailable interface cannot confirm the target")
    }

    func testPowerActionIsIgnoredWithoutWiFiHardware() async {
        let scanner = FakeWiFiPowerScanner()
        let controller = WiFiNetworkController(scanWorker: scanner)
        let store = makeStore(
            scanner: scanner,
            controller: controller,
            wifiMonitor: CountingWiFiMonitor(),
            wifiState: .unavailable
        )

        store.setWiFiPower(false)
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(scanner.powerValues, [], "no radio means no power write")
    }

    // MARK: - Helpers

    private func makeView(
        intent: PanelSummaryIntent,
        showsWiFiPowerControl: Bool,
        wifiPowerIsOn: Bool,
        title: String? = nil,
        subtitle: String = "192.168.1.20 · 5 GHz"
    ) -> NetworkStatusView {
        NetworkStatusView(
            showsWiFiPowerControl: showsWiFiPowerControl,
            wifiPowerIsOn: wifiPowerIsOn,
            wifiPowerCanSet: true,
            wifiPowerRequiresConfirmation: false,
            wifiPowerFailed: false,
            state: PanelSummaryState(
                title: title ?? (intent == .wiredDetails ? "USB Ethernet" : "Example Network"),
                subtitle: subtitle,
                measurements: nil,
                symbol: .symbol(
                    name: intent == .wiredDetails ? "cable.connector" : "wifi",
                    variableValue: nil,
                    fallback: nil
                ),
                tint: .secondary,
                accessibilityLabel: "Network",
                accessibilityValue: "Connected",
                showsSettings: true,
                intent: intent
            ),
            onOpenWiFiDetails: { _ in },
            onOpenWiredDetails: {},
            onRequestNameAccess: {},
            onOpenWiFiSettings: {},
            onOpenNetworkSettings: {},
            onOpenLocationSettings: {}
        )
    }

    private func makeDefaultsSuite() -> (defaults: UserDefaults, name: String) {
        let name = "StatusTrioCoreTests.WiFiPower.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (defaults, name)
    }

    private func clear(_ suite: (defaults: UserDefaults, name: String)) {
        suite.defaults.removePersistentDomain(forName: suite.name)
    }

    private func makeLocalization() throws -> Localization {
        let suite = makeDefaultsSuite()
        defer { clear(suite) }
        return Localization(defaults: suite.defaults, preferredLanguages: ["en"])
    }

    private func makeStore(
        scanner: FakeWiFiPowerScanner,
        controller: WiFiNetworkController,
        wifiMonitor: CountingWiFiMonitor,
        wifiState: WiFiState
    ) -> SystemStatusStore {
        SystemStatusStore(
            batteryMonitor: QuietBatteryMonitor(),
            wifiMonitor: wifiMonitor,
            volumeMonitor: QuietVolumeMonitor(),
            wifiNetworks: controller,
            initialSnapshot: StatusSnapshot(
                battery: .placeholder,
                wifi: WiFiStatus(state: wifiState, rssi: -55),
                volume: .placeholder
            )
        )
    }

    private func render<V: View>(_ view: V) throws -> SummaryActionAlignmentProbe {
        let suite = makeDefaultsSuite()
        defer { clear(suite) }
        let localization = Localization(defaults: suite.defaults, preferredLanguages: ["en"])

        let hosting = NSHostingView(
            rootView: view
                .padding(14)
                .frame(width: 330)
                .background(Color(white: 0.96))
                .environmentObject(localization)
                .environment(\.colorScheme, .light)
        )
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        return try XCTUnwrap(SummaryActionAlignmentProbe(hosting))
    }

    private func makeStartedStore(
        wifiState: WiFiState,
        powerSucceeds: Bool
    ) -> (store: SystemStatusStore, scanner: FakeWiFiPowerScanner, monitor: CountingWiFiMonitor) {
        let scanner = FakeWiFiPowerScanner()
        scanner.powerSucceeds = powerSucceeds
        let controller = WiFiNetworkController(scanWorker: scanner)
        let monitor = CountingWiFiMonitor()
        let store = makeStore(
            scanner: scanner,
            controller: controller,
            wifiMonitor: monitor,
            wifiState: wifiState
        )
        store.start()
        addTeardownBlock { store.stop() }
        return (store, scanner, monitor)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for the Wi-Fi power state")
    }
}

// MARK: - Fixtures

private final class FakeWiFiPowerScanner: WiFiNetworkScanning, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [Bool] = []
    var powerSucceeds = true
    var scanResult: WiFiScanWorkerResult = .success(
        WiFiScanPayload(networks: [], details: .unavailable)
    )

    var powerValues: [Bool] { lock.withLock { calls } }

    func scan(completion: @escaping @Sendable (WiFiScanWorkerResult) -> Void) {
        completion(scanResult)
    }

    func setPower(_ isOn: Bool, completion: @escaping @Sendable (Bool) -> Void) {
        lock.withLock { calls.append(isOn) }
        completion(powerSucceeds)
    }
}

@MainActor
private final class CountingWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>
    private let continuation: AsyncStream<WiFiStatus>.Continuation
    private(set) var refreshCount = 0

    init() {
        (updates, continuation) = AsyncStream.makeStream()
    }

    func send(_ value: WiFiStatus) { continuation.yield(value) }
    func start() {}
    func stop() {}
    func refresh() { refreshCount += 1 }
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class QuietBatteryMonitor: BatteryMonitoring {
    let updates = AsyncStream<BatteryStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class QuietVolumeMonitor: VolumeMonitoring {
    let updates = AsyncStream<VolumeStatus> { $0.finish() }
    let betterDisplayCatalogUpdates = AsyncStream<BetterDisplayCatalogUpdate> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func setDetailsVisible(_ visible: Bool) {}
    func setDisplayAsleep(_ asleep: Bool) {}
    func topologyChanged() {}
    func setExternalVolumeConfigurations(
        _ configurations: [String: ExternalVolumeConfiguration]
    ) {}
    func refreshBetterDisplayDevices() {}
}
