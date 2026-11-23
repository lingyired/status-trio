import Foundation
import Testing
@testable import StatusTrioCore

@MainActor
struct BluetoothBatteryControllerTests {
    @Test func batteryReadsOnlyWhileEnabledAndControllerIsActive() async {
        let deviceReader = BluetoothPairedDeviceReaderStub(result: .success([
            BluetoothDevice(id: "AC:90:85:C2:9C:1F", name: "AirPods", kind: .audio, isConnected: true)
        ]))
        let batteryReader = BluetoothBatteryReaderStub(result: [
            BluetoothBatteryReader.normalizedAddress("AC:90:85:C2:9C:1F"): BluetoothBatteryLevel(
                deviceAddress: "AC:90:85:C2:9C:1F",
                main: nil,
                left: 85,
                right: 80,
                caseLevel: 70
            )
        ])
        let monitor = BluetoothBatteryStateMonitorStub()
        let controller = BluetoothDeviceController(
            worker: deviceReader,
            stateMonitor: monitor,
            batteryReader: batteryReader,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )

        controller.requestBatteryLevels("test")
        controller.activate()
        await waitUntil { batteryReader.readCount == 1 && controller.batteryLevels.isEmpty == false }

        #expect(controller.batteryLevels.count == 1)
        #expect(controller.batteryLevels[BluetoothBatteryReader.normalizedAddress("ac9085c29c1f")]?.summary == "L 85% · R 80% · Case 70%")
        #expect(batteryReader.readCount == 1)

        controller.releaseBatteryLevels("test")
        #expect(controller.batteryLevels.isEmpty)
        #expect(batteryReader.readCount == 1)

        controller.deactivate()
        controller.requestBatteryLevels("test")
        await Task.yield()

        #expect(batteryReader.readCount == 1)
    }

    @Test func disablingBatteryLevelsDiscardsAnInFlightResult() async {
        let deviceReader = BluetoothPairedDeviceReaderStub(result: .success([]))
        let batteryReader = BlockingBluetoothBatteryReader()
        let monitor = BluetoothBatteryStateMonitorStub()
        let controller = BluetoothDeviceController(
            worker: deviceReader,
            stateMonitor: monitor,
            batteryReader: batteryReader,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )

        controller.requestBatteryLevels("test")
        controller.activate()
        await waitUntil { batteryReader.readCount == 1 }

        controller.releaseBatteryLevels("test")
        batteryReader.finish(with: [
            BluetoothBatteryReader.normalizedAddress("AC:90:85:C2:9C:1F"): BluetoothBatteryLevel(
                deviceAddress: "AC:90:85:C2:9C:1F",
                main: 90,
                left: nil,
                right: nil,
                caseLevel: nil
            )
        ])
        await Task.yield()

        #expect(controller.batteryLevels.isEmpty)
    }

    /// No claim, no read: a session that never asked for levels stays on the
    /// connected-device read, whatever devices are paired.
    @Test func batteryReadsStayOffWithoutAClaim() async {
        let deviceReader = BluetoothPairedDeviceReaderStub(result: .success([
            BluetoothDevice(id: "AC:90:85:C2:9C:1F", name: "MX Master 3", kind: .peripheral(.mouse), isConnected: true)
        ]))
        let batteryReader = BluetoothBatteryReaderStub(result: [:])
        let controller = BluetoothDeviceController(
            worker: deviceReader,
            stateMonitor: BluetoothBatteryStateMonitorStub(),
            batteryReader: batteryReader,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )

        controller.releaseBatteryLevels("test")
        controller.activate()
        await waitUntil { deviceReader.readCount == 1 }

        #expect(batteryReader.readCount == 0)
        #expect(controller.batteryLevels.isEmpty)
    }

    /// A connected AirPods entry is what enables the level read, and leaving
    /// the summary turns it back off.
    @Test func batteryReadsFollowConnectedAirPods() async {
        let deviceReader = BluetoothPairedDeviceReaderStub(result: .success([
            BluetoothDevice(id: "AC:90:85:C2:9C:1F", name: "AirPods Pro", kind: .audio, isConnected: true)
        ]))
        let batteryReader = BluetoothBatteryReaderStub(result: [
            BluetoothBatteryReader.normalizedAddress("AC:90:85:C2:9C:1F"): BluetoothBatteryLevel(
                deviceAddress: "AC:90:85:C2:9C:1F",
                main: nil,
                left: 85,
                right: 80,
                caseLevel: 70
            )
        ])
        let controller = BluetoothDeviceController(
            worker: deviceReader,
            stateMonitor: BluetoothBatteryStateMonitorStub(),
            batteryReader: batteryReader,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )

        controller.requestBatteryLevels("test")
        controller.activate()
        await waitUntil { !controller.batteryLevels.isEmpty }

        #expect(batteryReader.readCount == 1)
        #expect(controller.batteryLevels[BluetoothBatteryReader.normalizedAddress("ac9085c29c1f")]?.summary == "L 85% · R 80% · Case 70%")

        controller.releaseBatteryLevels("test")

        #expect(controller.batteryLevels.isEmpty)
        #expect(batteryReader.readCount == 1)
    }

    /// A report that could not be read is not the same as "no device has a
    /// level": the page has to say so once, and the controller must not publish
    /// levels it never read.
    @Test func aFailedReportIsReportedAndPublishesNoLevels() async {
        let batteryReader = BluetoothBatteryReaderStub(result: nil)
        let controller = makeController(batteryReader: batteryReader)

        controller.requestBatteryLevels("test")
        controller.activate()
        await waitUntil { controller.batteryLevelsReadFailed }

        #expect(controller.batteryLevels.isEmpty)
        #expect(controller.batteryLevelsReadFailed)
    }

    /// An empty report is a successful read, so it clears the failure rather
    /// than standing in for one.
    @Test func aLaterEmptyReportClearsTheFailure() async {
        let batteryReader = BluetoothBatteryReaderStub(result: nil)
        let controller = makeController(batteryReader: batteryReader)

        controller.requestBatteryLevels("test")
        controller.activate()
        await waitUntil { controller.batteryLevelsReadFailed }

        batteryReader.result = [:]
        controller.requestBatteryLevels("test")
        await waitUntil { batteryReader.readCount == 2 && !controller.batteryLevelsReadFailed }

        #expect(controller.batteryLevels.isEmpty)
        #expect(controller.batteryLevelsReadFailed == false)
    }

    /// A level is published exactly as read: an unchanged percentage and a
    /// one-point drift are both fresh readings, not a signal to suppress or
    /// "correct". Pins that the controller never invents staleness from a value
    /// merely repeating, and never dedupes consecutive reads away.
    @Test func everyReadPublishesEvenWhenTheLevelRepeatsOrBarelyChanges() async {
        let batteryReader = BluetoothBatteryReaderStub(result: batteryLevel(30))
        let controller = makeController(batteryReader: batteryReader)

        controller.requestBatteryLevels("test")
        controller.activate()
        await waitUntil { controller.batteryLevels[batteryKey]?.main == 30 }

        // Same value again: still a fresh read, still published.
        batteryReader.result = batteryLevel(30)
        controller.requestBatteryLevels("test")
        await waitUntil { batteryReader.readCount >= 2 }
        await waitUntil { controller.batteryLevels[batteryKey]?.main == 30 }

        // A one-point change is published too (30, 30, 29 in a row).
        batteryReader.result = batteryLevel(29)
        controller.requestBatteryLevels("test")
        await waitUntil { controller.batteryLevels[batteryKey]?.main == 29 }

        controller.deactivate()
    }

    // MARK: - Helpers

    private var batteryKey: String { "AC9085C29C1F" }

    private func batteryLevel(_ main: Int) -> [String: BluetoothBatteryLevel] {
        [batteryKey: BluetoothBatteryLevel(
            deviceAddress: "AC:90:85:C2:9C:1F", main: main, left: nil, right: nil, caseLevel: nil)]
    }

    /// Releasing the last claim drops the failure together with the levels it
    /// belonged to.
    @Test func releasingTheClaimClearsTheFailure() async {
        let batteryReader = BluetoothBatteryReaderStub(result: nil)
        let controller = makeController(batteryReader: batteryReader)

        controller.requestBatteryLevels("test")
        controller.activate()
        await waitUntil { controller.batteryLevelsReadFailed }

        controller.releaseBatteryLevels("test")

        #expect(controller.batteryLevelsReadFailed == false)
    }

    @Test func primaryLevelsOnlyPublishForCurrentlyConnectedAddresses() async throws {
        let deviceReader = BluetoothPairedDeviceReaderStub(result: .success([
            BluetoothDevice(id: "ac-90-85-c2-9c-1f", name: "AirPods", kind: .audio, isConnected: true),
            BluetoothDevice(id: "00:11:22:33:44:55", name: "Old AirPods", kind: .audio, isConnected: false)
        ]))
        let batteryReader = BluetoothBatteryReaderStub(result: [
            "AC9085C29C1F": BluetoothBatteryLevel(
                deviceAddress: "AC:90:85:C2:9C:1F", main: 90, left: nil, right: nil, caseLevel: nil),
            "001122334455": BluetoothBatteryLevel(
                deviceAddress: "00-11-22-33-44-55", main: 12, left: nil, right: nil, caseLevel: nil),
            "AABBCCDDEEFF": BluetoothBatteryLevel(
                deviceAddress: "AA:BB:CC:DD:EE:FF", main: 20, left: nil, right: nil, caseLevel: nil)
        ])
        let controller = BluetoothDeviceController(
            worker: deviceReader, stateMonitor: BluetoothBatteryStateMonitorStub(),
            batteryReader: batteryReader, notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        defer { controller.deactivate() }
        controller.requestBatteryLevels("test")
        controller.activate()
        await waitUntil { !controller.batteryLevels.isEmpty }
        #expect(controller.batteryLevels.keys.sorted() == ["AC9085C29C1F"])
        let localization = Localization(
            defaults: UserDefaults(suiteName: "BluetoothBatteryControllerTests.\(UUID().uuidString)")!,
            preferredLanguages: ["en"]
        )
        let panel = BluetoothPanelMapper.map(
            availability: controller.availability, devices: controller.devices,
            batteryLevels: controller.batteryLevels, actionStates: [:], nearbyDevices: [],
            batteryLevelsReadFailed: controller.batteryLevelsReadFailed, isExpanded: false,
            options: .standard, showsBatteryLevels: true, showsNearbyBatteryDevices: false,
            confirmingAddress: nil, localization: localization
        )
        let row = try #require(panel.pairedRows.first { $0.address == "001122334455" })
        #expect(row.batteryText == nil)
        #expect(row.batterySegments == nil)
        #expect(!row.accessibilityValue.contains("%"))
        #expect(row.actionEnabled)
        #expect(row.actionTitle == localization.string(.bluetoothActionConnect))
    }

    @Test(arguments: [false, true])
    func snapshotsExpireLevelsAndLateReadsCannotRestoreThem(usesAccessory: Bool) async {
        let connected = BluetoothDevice(id: "AC:90:85:C2:9C:1F", name: "AirPods", kind: .audio, isConnected: true)
        let disconnected = BluetoothDevice(id: connected.id, name: connected.name, kind: .audio, isConnected: false)
        let deviceReader = BluetoothPairedDeviceReaderStub(result: .success([connected]))
        let batteryReader = BlockingBluetoothBatteryReader()
        let controller = BluetoothDeviceController(
            worker: deviceReader, stateMonitor: BluetoothBatteryStateMonitorStub(),
            batteryReader: batteryReader,
            accessoryBatteryReader: usesAccessory ? BluetoothAccessoryBatteryReaderStub() : nil,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        defer { controller.deactivate() }
        let levels = ["AC9085C29C1F": BluetoothBatteryLevel(
            deviceAddress: connected.id, main: 90, left: nil, right: nil, caseLevel: nil)]
        controller.requestBatteryLevels("test")
        controller.activate()
        await waitUntil { batteryReader.readCount == 1 }
        batteryReader.finish(with: usesAccessory ? nil : levels)
        await waitUntil { !controller.batteryLevels.isEmpty }

        controller.requestBatteryLevels("test")
        let lateCompletion = batteryReader.completion
        deviceReader.result = .success([disconnected])
        controller.refresh()
        await waitUntil { batteryReader.readCount == 3 }
        #expect(controller.batteryLevels.isEmpty)
        lateCompletion?(levels)
        batteryReader.finish(with: nil)
        await waitUntil { controller.batteryLevelsReadFailed }
        #expect(controller.batteryLevels.isEmpty)
        // A warm claim supersedes the previous request and still filters the result.
        controller.requestBatteryLevels("test")
        batteryReader.finish(with: levels)
        await waitUntil { !controller.batteryLevelsReadFailed }
        #expect(controller.batteryLevels.isEmpty)
        #expect(!controller.batteryLevelsReadFailed)

        deviceReader.result = .success([connected])
        controller.refresh()
        await waitUntil { batteryReader.readCount == 5 }
        batteryReader.finish(with: usesAccessory ? nil : levels)
        await waitUntil { !controller.batteryLevels.isEmpty }
        #expect(controller.batteryLevels["AC9085C29C1F"]?.main == 90)

        controller.releaseBatteryLevels("test")
        deviceReader.result = .success([])
        controller.refresh()
        await waitUntil { controller.devices.isEmpty }
        #expect(controller.batteryLevels.isEmpty)
        controller.requestBatteryLevels("test")
        batteryReader.finish(with: levels)
        await waitUntil { controller.hasCompletedBatteryRead }
        #expect(controller.batteryLevels.isEmpty)
    }

    /// Only the reader's answer differs between these cases.
    private func makeController(
        batteryReader: BluetoothBatteryReaderStub
    ) -> BluetoothDeviceController {
        BluetoothDeviceController(
            worker: BluetoothPairedDeviceReaderStub(result: .success([
                BluetoothDevice(id: "AC:90:85:C2:9C:1F", name: "AirPods Pro", kind: .audio, isConnected: true)
            ])),
            stateMonitor: BluetoothBatteryStateMonitorStub(),
            batteryReader: batteryReader,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("Timed out waiting for Bluetooth battery state")
    }
}

private final class BluetoothPairedDeviceReaderStub: BluetoothPairedDeviceReading {
    var result: BluetoothWorkerResult
    private(set) var readCount = 0

    init(result: BluetoothWorkerResult) {
        self.result = result
    }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        readCount += 1
        completion(result)
    }
}

private final class BluetoothBatteryReaderStub: BluetoothBatteryReading {
    var result: [String: BluetoothBatteryLevel]?
    private(set) var readCount = 0

    init(result: [String: BluetoothBatteryLevel]?) {
        self.result = result
    }

    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]?) -> Void) {
        readCount += 1
        completion(result)
    }
}

private final class BlockingBluetoothBatteryReader: BluetoothBatteryReading {
    private(set) var readCount = 0
    private(set) var completion: (@Sendable ([String: BluetoothBatteryLevel]?) -> Void)?

    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]?) -> Void) {
        readCount += 1
        self.completion = completion
    }

    func finish(with levels: [String: BluetoothBatteryLevel]?) {
        completion?(levels)
    }
}

private final class BluetoothAccessoryBatteryReaderStub: BluetoothAccessoryBatteryReading {
    func read(completion: @escaping @Sendable ([BluetoothAccessoryBatteryLevel]?) -> Void) {
        completion([BluetoothAccessoryBatteryLevel(
            identifier: "airpods", name: "AirPods", vendorID: nil, productID: nil,
            part: nil, percentage: 90
        )])
    }
}

@MainActor
private final class BluetoothBatteryStateMonitorStub: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus = .allowed

    func start() {
        onStateChange?(authorization, .poweredOn)
    }

    func stop() {}
}

/// The summary row and the detail page both need battery levels, and SwiftUI
/// may run their hooks in either order. A claim count makes the outcome the
/// same either way; the boolean it replaced let the last writer win, which
/// left the detail page showing "Unavailable" for every device.
@MainActor
struct BluetoothBatteryLevelClaimTests {
    private func makeController() -> (BluetoothDeviceController, BluetoothBatteryReaderStub) {
        let batteryReader = BluetoothBatteryReaderStub(result: [
            BluetoothBatteryReader.normalizedAddress("AC:90:85:C2:9C:1F"): BluetoothBatteryLevel(
                deviceAddress: "AC:90:85:C2:9C:1F", main: nil, left: 85, right: 80, caseLevel: 70)
        ])
        let controller = BluetoothDeviceController(
            worker: BluetoothPairedDeviceReaderStub(result: .success([
                BluetoothDevice(id: "AC:90:85:C2:9C:1F", name: "AirPods Pro", kind: .audio, isConnected: true)
            ])),
            stateMonitor: BluetoothBatteryStateMonitorStub(),
            batteryReader: batteryReader,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        return (controller, batteryReader)
    }

    /// Incoming appears first, then the outgoing releases: the claim must hold.
    @Test func detailClaimSurvivesTheSummaryReleasingAfterwards() {
        let (controller, _) = makeController()
        controller.activate()

        controller.requestBatteryLevels("summary")
        controller.requestBatteryLevels("detail")
        controller.releaseBatteryLevels("summary")

        #expect(controller.isBatteryLevelsRequested)
        controller.deactivate()
    }

    /// The outgoing releases first, then the incoming claims: same outcome.
    @Test func detailClaimSurvivesTheSummaryReleasingFirst() {
        let (controller, _) = makeController()
        controller.activate()

        controller.requestBatteryLevels("summary")
        controller.releaseBatteryLevels("summary")
        controller.requestBatteryLevels("detail")

        #expect(controller.isBatteryLevelsRequested)
        controller.deactivate()
    }

    /// Two summary appearances (returning from the detail page) must not leak
    /// a claim that outlives the view.
    @Test func repeatedClaimsReleaseOnTheSingleOwner() {
        let (controller, _) = makeController()
        controller.activate()

        controller.requestBatteryLevels("summary")
        controller.requestBatteryLevels("summary")
        controller.releaseBatteryLevels("summary")

        #expect(controller.isBatteryLevelsRequested == false)
        controller.deactivate()
    }

    /// Closing the popover drops every outstanding claim.
    @Test func deactivatingReleasesEveryClaim() {
        let (controller, _) = makeController()
        controller.activate()
        controller.requestBatteryLevels("summary")
        controller.requestBatteryLevels("detail")

        controller.deactivate()

        #expect(controller.isBatteryLevelsRequested == false)
    }
}
