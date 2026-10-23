import AppKit
import Foundation
import Testing
@testable import StatusTrioCore

@MainActor
struct StatusBarAccessibilityUpdateTests {
    /// Several emissions in one turn must land as one update carrying the
    /// newest state. One task per emission would let an earlier capture write
    /// last and leave VoiceOver reading a value the app no longer shows.
    @Test func testABurstOfLanguageChangesAppliesTheNewestValueExactlyOnce() async throws {
        let domain = "StatusBarAccessibility.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }

        let battery = BatteryStatus(
            rawPercentage: 55,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: false
        )
        let store = SystemStatusStore(
            batteryMonitor: IdleAccessibilityBatteryMonitor(),
            wifiMonitor: IdleAccessibilityWiFiMonitor(),
            volumeMonitor: IdleAccessibilityVolumeMonitor(),
            initialSnapshot: StatusSnapshot(
                battery: battery,
                wifi: .placeholder,
                volume: .placeholder
            )
        )
        let settings = SettingsStore(defaults: defaults)
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let iconPresentation = makeTestIconPresentation(store: store, settings: settings)
        iconPresentation.start()
        defer { iconPresentation.stop() }

        let recorder = AccessibilityValueRecorder()
        let controller = StatusBarController(
            store: store,
            settings: settings,
            iconPresentation: iconPresentation,
            localization: localization,
            openSettings: {},
            quitAction: {},
            accessibilityValueDidChange: { recorder.record($0) }
        )
        defer { controller.setVisible(false) }

        await recorder.waitForUpdate(atLeast: 1)
        let settled = recorder.values.count
        #expect(settled == 1)

        localization.setPreference(.language(.french))
        localization.setPreference(.language(.german))
        localization.setPreference(.language(.japanese))

        await recorder.waitForUpdate(atLeast: settled + 1)
        try await Task.sleep(for: .milliseconds(120))

        #expect(recorder.values.count == settled + 1)
        let expected = AccessibilityPresentation.statusItemValue(
            store.snapshot,
            localization: localization
        )
        #expect(recorder.values.last == expected)
    }
}

@MainActor
private final class AccessibilityValueRecorder {
    private(set) var values: [String] = []

    func record(_ value: String) {
        values.append(value)
    }

    func waitForUpdate(atLeast count: Int) async {
        var spins = 0
        while values.count < count, spins < 400 {
            try? await Task.sleep(for: .milliseconds(5))
            spins += 1
        }
    }
}

@MainActor
private final class IdleAccessibilityBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>

    init() {
        (updates, _) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class IdleAccessibilityWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>

    init() {
        (updates, _) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class IdleAccessibilityVolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>

    init() {
        (updates, _) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func setDetailsVisible(_ visible: Bool) {}
}
