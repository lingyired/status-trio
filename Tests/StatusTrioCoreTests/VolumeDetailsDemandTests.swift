import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class VolumeDetailsDemandTests: XCTestCase {
    func testBatteryAndNetworkSectionsKeepVolumeDetailsOffWhilePopoverIsOpen() {
        let fixture = makeFixture(sections: [.battery, .network])
        defer { fixture.tearDown() }
        fixture.store.bindBluetoothSettings(fixture.settings)
        fixture.store.start()

        XCTAssertEqual(fixture.volumeMonitor.startCount, 1)
        XCTAssertFalse(fixture.volumeMonitor.detailsVisible)

        fixture.store.setPopoverVisible(true)

        XCTAssertTrue(fixture.store.isPopoverVisible)
        XCTAssertFalse(fixture.volumeMonitor.detailsVisible)
        XCTAssertFalse(
            fixture.volumeMonitor.detailsVisibility.contains(true),
            "battery and network sections must not request volume details"
        )
    }

    func testVolumeOrBluetoothSectionEnablesVolumeDetails() {
        for section in [PopupSection.volume, .bluetooth] {
            let fixture = makeFixture(sections: [section])
            defer { fixture.tearDown() }
            fixture.store.bindBluetoothSettings(fixture.settings)
            fixture.store.start()

            fixture.store.setPopoverVisible(true)

            XCTAssertTrue(
                fixture.volumeMonitor.detailsVisible,
                "\(section.rawValue) section should enable volume details"
            )
        }
    }

    func testOpenPopoverTracksSectionTransitionsAndRefreshesOnlyWhenDetailsTurnOn() {
        let fixture = makeFixture(sections: [])
        defer { fixture.tearDown() }
        fixture.store.bindBluetoothSettings(fixture.settings)
        fixture.store.start()
        fixture.store.setPopoverVisible(true)

        XCTAssertTrue(fixture.store.isPopoverVisible)
        XCTAssertFalse(fixture.volumeMonitor.detailsVisible)

        let visibilityCallsWhileOff = fixture.volumeMonitor.detailsVisibility.count
        let refreshesWhileOff = fixture.volumeMonitor.refreshDetailsVisibility.count
        fixture.settings.showsBluetoothDeviceList.toggle()
        XCTAssertFalse(fixture.volumeMonitor.detailsVisible)
        XCTAssertEqual(
            fixture.volumeMonitor.detailsVisibility.count,
            visibilityCallsWhileOff
        )
        XCTAssertEqual(
            fixture.volumeMonitor.refreshDetailsVisibility.count,
            refreshesWhileOff
        )

        fixture.settings.setPopupSection(.volume, enabled: true)
        XCTAssertTrue(fixture.volumeMonitor.detailsVisible)
        let afterVolumeEnabled = fixture.volumeMonitor.detailedRefreshCount
        XCTAssertGreaterThan(afterVolumeEnabled, 0)

        fixture.settings.showsBluetoothDeviceList.toggle()
        XCTAssertTrue(fixture.volumeMonitor.detailsVisible)
        XCTAssertEqual(
            fixture.volumeMonitor.detailedRefreshCount,
            afterVolumeEnabled,
            "An unrelated settings change must not repeat the detailed refresh"
        )

        fixture.settings.setPopupSection(.volume, enabled: false)
        XCTAssertFalse(fixture.volumeMonitor.detailsVisible)
        XCTAssertEqual(fixture.volumeMonitor.detailedRefreshCount, afterVolumeEnabled)

        fixture.settings.setPopupSection(.bluetooth, enabled: true)
        XCTAssertTrue(fixture.volumeMonitor.detailsVisible)
        let afterBluetoothEnabled = fixture.volumeMonitor.detailedRefreshCount
        XCTAssertGreaterThan(afterBluetoothEnabled, afterVolumeEnabled)

        fixture.settings.setPopupSection(.bluetooth, enabled: false)
        XCTAssertFalse(fixture.volumeMonitor.detailsVisible)
        XCTAssertEqual(fixture.volumeMonitor.detailedRefreshCount, afterBluetoothEnabled)
        XCTAssertTrue(fixture.store.isPopoverVisible)
    }

    func testSettingsAndPopoverOwnVolumeDetailsIndependently() {
        let fixture = makeFixture(sections: [])
        defer { fixture.tearDown() }
        fixture.store.bindBluetoothSettings(fixture.settings)
        fixture.store.start()

        fixture.store.setSettingsVisible(true)
        XCTAssertTrue(
            fixture.volumeMonitor.detailsVisible,
            "Settings should enable volume details while every popover section is off"
        )

        fixture.store.setPopoverVisible(true)
        fixture.store.setPopoverVisible(false)
        XCTAssertTrue(
            fixture.volumeMonitor.detailsVisible,
            "Settings should retain volume details after the popover closes"
        )

        fixture.store.setPopoverVisible(true)
        fixture.settings.setPopupSection(.volume, enabled: true)
        fixture.store.setSettingsVisible(false)
        XCTAssertTrue(
            fixture.volumeMonitor.detailsVisible,
            "An explicitly enabled volume section should retain details after Settings closes"
        )

        fixture.settings.setPopupSection(.volume, enabled: false)
        XCTAssertFalse(fixture.volumeMonitor.detailsVisible)

        fixture.store.setSettingsVisible(true)
        XCTAssertTrue(
            fixture.volumeMonitor.detailsVisible,
            "Settings should reacquire volume details without any popover section"
        )

        fixture.store.setPopoverVisible(false)
        XCTAssertTrue(fixture.volumeMonitor.detailsVisible)
        fixture.store.setSettingsVisible(false)
        XCTAssertFalse(fixture.volumeMonitor.detailsVisible)
    }

    func testUnboundSettingsKeepLegacyPopoverDetailsBehavior() {
        let fixture = makeFixture(sections: [])
        defer { fixture.tearDown() }
        fixture.store.start()

        XCTAssertFalse(fixture.volumeMonitor.detailsVisible)
        fixture.store.setPopoverVisible(true)
        XCTAssertTrue(fixture.volumeMonitor.detailsVisible)
        fixture.store.setPopoverVisible(false)
        XCTAssertFalse(fixture.volumeMonitor.detailsVisible)
    }

    func testRebindAppliesNewSettingsImmediatelyAndStopsObservingOldSettings() {
        let fixture = makeFixture(sections: [.battery, .network])
        defer { fixture.tearDown() }
        let newSuite = makeSuite()
        defer { newSuite.defaults.removePersistentDomain(forName: newSuite.name) }
        let newSettings = makeSettings(defaults: newSuite.defaults, sections: [.volume])
        fixture.store.start()
        fixture.store.setPopoverVisible(true)
        XCTAssertTrue(fixture.volumeMonitor.detailsVisible)

        fixture.store.bindBluetoothSettings(fixture.settings)
        XCTAssertFalse(
            fixture.volumeMonitor.detailsVisible,
            "Initial binding should apply the delivered section snapshot"
        )

        fixture.store.bindBluetoothSettings(newSettings)
        XCTAssertTrue(
            fixture.volumeMonitor.detailsVisible,
            "Rebinding should immediately apply the replacement settings"
        )

        newSettings.setPopupSection(.volume, enabled: false)
        XCTAssertFalse(fixture.volumeMonitor.detailsVisible)

        fixture.settings.setPopupSection(.volume, enabled: true)
        XCTAssertFalse(
            fixture.volumeMonitor.detailsVisible,
            "Changes to the previous settings store must not affect the rebind"
        )
    }

    private func makeFixture(
        sections: Set<PopupSection>
    ) -> VolumeDetailsFixture {
        let suite = makeSuite()
        let settings = makeSettings(defaults: suite.defaults, sections: sections)
        let volumeMonitor = VolumeDetailsMonitor()
        let profilerCache = BluetoothProfilerReportCache()
        let notificationCenter = NotificationCenter()
        let workspaceNotificationCenter = NotificationCenter()
        let bluetoothDevices = BluetoothDeviceController(
            worker: VolumeDetailsBluetoothReader(),
            stateMonitor: VolumeDetailsDeniedBluetoothStateMonitor(),
            batteryReader: VolumeDetailsBluetoothBatteryReader(),
            notificationCenter: notificationCenter,
            workspaceNotificationCenter: workspaceNotificationCenter
        )
        let store = SystemStatusStore(
            batteryMonitor: VolumeDemandBatteryMonitor(),
            wifiMonitor: VolumeDemandWiFiMonitor(),
            volumeMonitor: volumeMonitor,
            refreshInterval: .seconds(60),
            wakeNotificationCenter: NotificationCenter(),
            bluetoothDevices: bluetoothDevices,
            bluetoothProfilerCache: profilerCache
        )
        return VolumeDetailsFixture(
            defaults: suite.defaults,
            suiteName: suite.name,
            settings: settings,
            store: store,
            volumeMonitor: volumeMonitor
        )
    }

    private func makeSettings(
        defaults: UserDefaults,
        sections: Set<PopupSection>
    ) -> SettingsStore {
        let settings = SettingsStore(defaults: defaults)
        for section in PopupSection.allCases {
            settings.setPopupSection(section, enabled: sections.contains(section))
        }
        return settings
    }

    private func makeSuite() -> (defaults: UserDefaults, name: String) {
        let name = "StatusTrioCoreTests.VolumeDetailsDemand.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            fatalError("could not create isolated user defaults suite")
        }
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }
}

@MainActor
private struct VolumeDetailsFixture {
    let defaults: UserDefaults
    let suiteName: String
    let settings: SettingsStore
    let store: SystemStatusStore
    let volumeMonitor: VolumeDetailsMonitor

    func tearDown() {
        store.stop()
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private final class VolumeDemandBatteryMonitor: BatteryMonitoring {
    let updates = AsyncStream<BatteryStatus> { $0.finish() }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class VolumeDemandWiFiMonitor: WiFiMonitoring {
    let updates = AsyncStream<WiFiStatus> { $0.finish() }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

private final class VolumeDetailsBluetoothReader: BluetoothPairedDeviceReading {
    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        completion(.failed)
    }
}

private final class VolumeDetailsBluetoothBatteryReader: BluetoothBatteryReading {
    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]?) -> Void) {
        completion([:])
    }
}

@MainActor
private final class VolumeDetailsDeniedBluetoothStateMonitor: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus = .denied

    func start() {
        onStateChange?(authorization, .unknown)
    }

    func stop() {}
}

@MainActor
private final class VolumeDetailsMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>
    private let continuation: AsyncStream<VolumeStatus>.Continuation
    private(set) var startCount = 0
    private(set) var detailsVisible = false
    private(set) var detailsVisibility: [Bool] = []
    private(set) var refreshDetailsVisibility: [Bool] = []

    var detailedRefreshCount: Int {
        refreshDetailsVisibility.filter { $0 }.count
    }

    init() {
        (updates, continuation) = AsyncStream.makeStream()
    }

    func start() {
        startCount += 1
    }

    func stop() {
        continuation.finish()
    }

    func refresh() {
        refreshDetailsVisibility.append(detailsVisible)
    }

    func recover() {}

    func setDetailsVisible(_ visible: Bool) {
        detailsVisible = visible
        detailsVisibility.append(visible)
    }
}
