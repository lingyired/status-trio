import CoreGraphics
import XCTest
@testable import StatusTrioCore

/// External brightness changes on the built-in panel (brightness keys, Control
/// Center, Settings) must reach the panel without reopening it. These tests use
/// an injected fake of the narrow DisplayServices surface; the real private
/// framework and physical brightness effect stay NOT RUN.
@MainActor
final class DisplayServicesBrightnessChangeTests: XCTestCase {
    private final class FakeDisplayServicesAPI: DisplayServicesBrightnessAPI, @unchecked Sendable {
        var isAvailable = true
        var value: Float = 0.2
        var getCount = 0
        var registeredDisplays: [CGDirectDisplayID] = []
        var unregisteredDisplays: [CGDirectDisplayID] = []
        var observers: [UInt32: CGDirectDisplayID] = [:]
        var registrationSucceeds = true

        func getBrightness(
            _ displayID: CGDirectDisplayID,
            _ value: UnsafeMutablePointer<Float>
        ) -> Int32 {
            getCount += 1
            value.pointee = self.value
            return 0
        }

        func setBrightness(_ displayID: CGDirectDisplayID, _ value: Float) -> Int32 {
            self.value = value
            return 0
        }

        func startBrightnessChangeNotifications(
            for displayID: CGDirectDisplayID, observerID: UInt32
        ) -> Bool {
            guard registrationSucceeds else { return false }
            registeredDisplays.append(displayID)
            observers[observerID] = displayID
            return true
        }

        func stopBrightnessChangeNotifications(for displayID: CGDirectDisplayID, observerID: UInt32) {
            unregisteredDisplays.append(displayID)
            observers.removeValue(forKey: observerID)
        }

        func emitChange(for displayID: CGDirectDisplayID) {
            for (observerID, registeredDisplay) in observers where registeredDisplay == displayID {
                NotificationCenter.default.post(
                    name: .displayServicesBrightnessDidChange,
                    object: NSNumber(value: observerID)
                )
            }
        }
    }

    private func settle() async {
        for _ in 0..<8 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(10))
    }

    private struct BuiltinCatalog: DisplayCatalogProviding {
        func currentDisplays() -> [DisplayDescriptor] {
            [DisplayDescriptor(id: "builtin", name: "Built-in", isBuiltin: true, displayID: 5)]
        }
    }

    func testMonitorDoesNotRegisterOrReadWhenShownOrReconfiguredDuringSleep() {
        let api = FakeDisplayServicesAPI()
        let monitor = BrightnessMonitor(
            catalog: BuiltinCatalog(),
            makeDisplayServices: { id, onUpdate in
                DisplayServicesBrightnessController(displayID: id, api: api, onUpdate: onUpdate)
            }
        )
        monitor.start()
        monitor.setDisplayAsleep(true)
        monitor.setDetailsVisible(true)
        monitor.refresh()
        monitor.recover()
        monitor.setBackend(.displayServices, forDisplayID: "builtin")
        monitor.setExternalBrightnessConfigurations(["external": .default])
        XCTAssertTrue(api.registeredDisplays.isEmpty)
        XCTAssertEqual(api.getCount, 0)

        monitor.setDisplayAsleep(false)
        monitor.refresh()
        XCTAssertEqual(api.registeredDisplays, [5])
        XCTAssertGreaterThan(api.getCount, 0)
        monitor.setDetailsVisible(false)
        XCTAssertEqual(api.unregisteredDisplays, [5])
        monitor.stop()
    }

    func testBrightnessChangeNotificationPushesTheNewValue() async {
        let api = FakeDisplayServicesAPI()
        var updates: [DisplayServicesBrightnessUpdate] = []
        let controller = DisplayServicesBrightnessController(displayID: 5, api: api) {
            updates.append($0)
        }

        controller.start()
        XCTAssertEqual((updates.last?.scalar ?? -1), 0.2, accuracy: 0.0001)
        XCTAssertEqual(api.registeredDisplays, [5])

        // Simulate the user pressing a brightness key: DisplayServices posts its
        // C callback, which publishes the notification the controller observes.
        api.value = 0.6
        api.emitChange(for: 5)
        await settle()

        XCTAssertEqual(updates.last?.source, .displayServices)
        XCTAssertEqual(updates.last?.scalar ?? -1, 0.6, accuracy: 0.0001)
        controller.stop()
    }

    func testNotificationForAnotherDisplayDoesNotRefreshThisPanel() async {
        let api = FakeDisplayServicesAPI()
        var updates: [DisplayServicesBrightnessUpdate] = []
        let controller = DisplayServicesBrightnessController(displayID: 5, api: api) {
            updates.append($0)
        }

        controller.start()
        let otherAPI = FakeDisplayServicesAPI()
        let otherController = DisplayServicesBrightnessController(displayID: 9, api: otherAPI) { _ in }
        otherController.start()
        let countAfterStart = updates.count
        let readsAfterStart = api.getCount

        otherAPI.emitChange(for: 9)
        await settle()

        XCTAssertEqual(updates.count, countAfterStart)
        XCTAssertEqual(api.getCount, readsAfterStart)
        controller.stop()
        otherController.stop()
    }

    func testStopUnregistersAndIgnoresLaterNotifications() async {
        let api = FakeDisplayServicesAPI()
        var updates: [DisplayServicesBrightnessUpdate] = []
        let controller = DisplayServicesBrightnessController(displayID: 5, api: api) {
            updates.append($0)
        }

        controller.start()
        let oldObserverID = api.observers.keys.first!
        controller.stop()
        XCTAssertEqual(api.unregisteredDisplays, [5])
        let countAfterStop = updates.count

        api.value = 0.9
        NotificationCenter.default.post(
            name: .displayServicesBrightnessDidChange,
            object: NSNumber(value: oldObserverID)
        )
        await settle()

        XCTAssertEqual(updates.count, countAfterStop)
    }

    func testReleasingStartedControllerUnregistersWithoutExplicitStop() {
        let api = FakeDisplayServicesAPI()
        weak var releasedController: DisplayServicesBrightnessController?
        do {
            let controller = DisplayServicesBrightnessController(displayID: 5, api: api) { _ in }
            releasedController = controller
            controller.start()
        }
        XCTAssertNil(releasedController)
        XCTAssertEqual(api.unregisteredDisplays, [5], "Native observers must not outlive their controller")
    }

    func testSameDisplayControllersOwnIndependentNativeSubscriptions() async {
        let api = FakeDisplayServicesAPI()
        let old = DisplayServicesBrightnessController(displayID: 5, api: api) { _ in }
        var updates: [DisplayServicesBrightnessUpdate] = []
        let current = DisplayServicesBrightnessController(displayID: 5, api: api) { updates.append($0) }
        old.start()
        current.start()
        XCTAssertEqual(api.observers.count, 2)
        old.stop()
        XCTAssertEqual(api.observers.count, 1)

        api.value = 0.7
        api.emitChange(for: 5)
        await settle()
        XCTAssertEqual(updates.last?.scalar ?? -1, 0.7, accuracy: 0.0001)
        current.stop()
        XCTAssertTrue(api.observers.isEmpty)
    }

    func testRestartRejectsPreviouslyQueuedNotification() async {
        let api = FakeDisplayServicesAPI()
        let controller = DisplayServicesBrightnessController(displayID: 5, api: api) { _ in }
        controller.start()
        let oldObserverID = api.observers.keys.first!
        api.emitChange(for: 5) // Its Task has not run on the MainActor yet.
        controller.stop()
        controller.start()
        XCTAssertNotEqual(api.observers.keys.first, oldObserverID)
        let readsAfterRestart = api.getCount
        NotificationCenter.default.post(
            name: .displayServicesBrightnessDidChange, object: NSNumber(value: oldObserverID)
        )
        await settle()
        XCTAssertEqual(api.getCount, readsAfterRestart)
        controller.stop()
    }

    func testRegistrationFailureStillAllowsExplicitRefreshAndHasNothingToUnregister() {
        let api = FakeDisplayServicesAPI()
        api.registrationSucceeds = false
        var updates: [DisplayServicesBrightnessUpdate] = []
        let controller = DisplayServicesBrightnessController(displayID: 5, api: api) { updates.append($0) }
        controller.start()
        api.value = 0.4
        controller.refresh()
        XCTAssertEqual(updates.last?.scalar ?? -1, 0.4, accuracy: 0.0001)
        controller.stop()
        XCTAssertTrue(api.unregisteredDisplays.isEmpty)
    }

    func testUnavailableRegistrationFallsBackToManualRefreshOnly() async {
        let api = FakeDisplayServicesAPI()
        api.isAvailable = false
        var updates: [DisplayServicesBrightnessUpdate] = []
        let controller = DisplayServicesBrightnessController(displayID: 5, api: api) {
            updates.append($0)
        }

        controller.start()
        XCTAssertTrue(api.registeredDisplays.isEmpty)
        XCTAssertEqual(updates.last?.scalar, nil)
        XCTAssertEqual(updates.last?.source, .unavailable(.noBackend))
        controller.stop()
        XCTAssertTrue(api.unregisteredDisplays.isEmpty)
    }
}
