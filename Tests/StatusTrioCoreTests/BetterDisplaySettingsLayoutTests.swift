import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class BetterDisplaySettingsLayoutTests: XCTestCase {
    func testRefreshingDisplayCatalogDoesNotExpandRowsToFitFullUUIDLabels() async throws {
        let suiteName = "BetterDisplaySettingsLayoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removeTestSuite(named: suiteName) }
        let settings = SettingsStore(defaults: defaults)
        settings.setExternalVolumeConfiguration(
            ExternalVolumeConfiguration(backend: .betterDisplay, betterDisplayUUID: nil),
            for: "audio-display"
        )
        let volume = LayoutVolumeMonitor()
        let output = AudioOutputDevice(
            id: 41, name: "XV272U", uid: "audio-display", isCurrent: true
        )
        let status = SystemStatusStore(
            batteryMonitor: LayoutBatteryMonitor(),
            wifiMonitor: LayoutWiFiMonitor(),
            volumeMonitor: volume,
            wakeNotificationCenter: NotificationCenter(),
            initialSnapshot: StatusSnapshot(
                battery: .placeholder,
                wifi: .placeholder,
                volume: VolumeStatus(
                    scalar: nil, isMuted: false, deviceName: output.name,
                    currentDevice: output, outputDevices: [output]
                )
            )
        )
        status.start()
        defer { status.stop() }
        let hosting = NSHostingView(
            rootView: AudioSectionView(
                store: settings, statusStore: status, previewIsDark: .constant(true)
            )
            .environmentObject(Localization(defaults: defaults, preferredLanguages: ["zh-Hans"]))
            .environmentObject(ChargingEffectClock())
        )
        let size = NSSize(width: 530, height: 530)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(
            descendants(of: hosting).first { $0 is NSScrollView } as? NSScrollView
        )
        let document = try XCTUnwrap(scroll.documentView)
        let originalHeight = document.frame.height
        XCTAssertGreaterThan(originalHeight, 500, "The audio groups must actually be laid out.")

        let display = BetterDisplayDevice(
            uuid: "12345678-1234-1234-1234-123456789ABC",
            name: "XV272U"
        )
        await refreshCatalog([display], monitor: volume, status: status)
        XCTAssertEqual(status.betterDisplayDevices.count, 1)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(
            document.frame.height, originalHeight + 80,
            """
            Adding a catalog option without changing the selection must not squeeze \
            the display description into a narrow column and expand the page by hundreds of points.
            """
        )

        settings.setExternalVolumeConfiguration(
            ExternalVolumeConfiguration(backend: .betterDisplay, betterDisplayUUID: display.uuid),
            for: "audio-display"
        )
        hosting.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(document.frame.height, originalHeight + 80)

        await refreshCatalog(
            [BetterDisplayDevice(
                uuid: display.uuid,
                name: "External Display With A Very Long Custom Name For The Desk"
            )],
            monitor: volume, status: status
        )
        hosting.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(document.frame.height, originalHeight + 80)

        await refreshCatalog([], monitor: volume, status: status)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(
            document.frame.height, originalHeight + 80,
            "An unavailable saved display must keep the same bounded control width."
        )
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func refreshCatalog(
        _ devices: [BetterDisplayDevice],
        monitor: LayoutVolumeMonitor,
        status: SystemStatusStore
    ) async {
        let received = expectation(description: "Refreshed display catalog reaches the settings store")
        let subscription = status.$betterDisplayState.dropFirst().sink { value in
            if value.devices == devices && value.isCatalogLoaded { received.fulfill() }
        }
        defer { subscription.cancel() }
        status.refreshBetterDisplayDevices()
        monitor.sendCatalog(devices)
        await fulfillment(of: [received], timeout: 2)
    }
}

@MainActor
private final class LayoutVolumeMonitor: VolumeMonitoring {
    let updates = AsyncStream<VolumeStatus> { $0.finish() }
    let betterDisplayCatalogUpdates: AsyncStream<BetterDisplayCatalogUpdate>
    private let continuation: AsyncStream<BetterDisplayCatalogUpdate>.Continuation

    init() {
        (betterDisplayCatalogUpdates, continuation) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() { continuation.finish() }
    func refresh() {}
    func recover() {}
    func sendCatalog(_ devices: [BetterDisplayDevice]) {
        continuation.yield(
            BetterDisplayCatalogUpdate(devices: devices, availability: .deviceUnassociated)
        )
    }
}

@MainActor
private final class LayoutBatteryMonitor: BatteryMonitoring {
    let updates = AsyncStream<BatteryStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class LayoutWiFiMonitor: WiFiMonitoring {
    let updates = AsyncStream<WiFiStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}
