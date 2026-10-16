import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class InputSourceControllerTests: XCTestCase {
    private let abc = RawInputSource(
        id: "com.apple.keylayout.ABC",
        localizedName: "ABC",
        languages: ["en"],
        iconImageURL: nil,
        isEnabled: true,
        isSelectCapable: true
    )
    private let pinyin = RawInputSource(
        id: "com.example.pinyin",
        localizedName: "Example 拼音",
        languages: ["zh-Hans"],
        iconImageURL: URL(fileURLWithPath: "/fixture/menu_icon.pdf"),
        isEnabled: true,
        isSelectCapable: true
    )

    func testStartReadsOnceAndPublishesResolvedState() {
        let reader = FakeInputSourceReader(current: abc.id, sources: [abc, pinyin])
        let controller = makeController(reader: reader)

        controller.start()

        XCTAssertEqual(controller.state.selectedID, abc.id)
        XCTAssertEqual(controller.state.sources.map(\.id), [abc.id, pinyin.id])
        XCTAssertEqual(controller.selectedDescriptor?.shortLabel, "A")
    }

    func testSelectedSourceNotificationRefreshesState() {
        let reader = FakeInputSourceReader(current: abc.id, sources: [abc, pinyin])
        let notifications = FakeInputSourceNotifications()
        let controller = makeController(reader: reader, notifications: notifications)
        controller.start()

        reader.current = pinyin.id
        notifications.emit(InputSourceNotifications.selectedSourceChanged)

        XCTAssertEqual(controller.state.selectedID, pinyin.id)
        XCTAssertEqual(controller.selectedDescriptor?.shortLabel, "拼")
    }

    func testEnabledSourcesNotificationRefreshesList() {
        let reader = FakeInputSourceReader(current: abc.id, sources: [abc])
        let notifications = FakeInputSourceNotifications()
        let controller = makeController(reader: reader, notifications: notifications)
        controller.start()

        reader.sources = [abc, pinyin]
        notifications.emit(InputSourceNotifications.enabledSourcesChanged)

        XCTAssertEqual(controller.state.sources.map(\.id), [abc.id, pinyin.id])
    }

    func testUnchangedRefreshesDoNotRepublish() {
        let reader = FakeInputSourceReader(current: abc.id, sources: [abc])
        let notifications = FakeInputSourceNotifications()
        let controller = makeController(reader: reader, notifications: notifications)
        controller.start()

        var published = 0
        let cancellable = controller.objectWillChange.sink { published += 1 }
        notifications.emit(InputSourceNotifications.selectedSourceChanged)
        notifications.emit(InputSourceNotifications.enabledSourcesChanged)

        XCTAssertEqual(published, 0, "an unchanged read must not invalidate observers")
        cancellable.cancel()
    }

    func testSelectRoutesThroughSwitcherAndConfirms() {
        let reader = FakeInputSourceReader(current: abc.id, sources: [abc, pinyin])
        let switcher = FakeInputSourceSwitcher(result: .selected) { [reader] id in
            reader.current = id
        }
        let scheduler = FakeInputSourceConfirmationScheduler()
        let controller = makeController(reader: reader, switcher: switcher, scheduler: scheduler)
        controller.start()

        controller.select(id: pinyin.id)

        XCTAssertEqual(switcher.requests, [pinyin.id])
        XCTAssertEqual(controller.state.selectedID, pinyin.id)
        XCTAssertNil(controller.selectionFailure)

        scheduler.runAllPending()
        XCTAssertNil(controller.selectionFailure)
    }

    func testSelectUnknownIDNeverCallsTheSwitcher() {
        let reader = FakeInputSourceReader(current: abc.id, sources: [abc])
        let switcher = FakeInputSourceSwitcher(result: .selected) { _ in }
        let controller = makeController(reader: reader, switcher: switcher)
        controller.start()

        controller.select(id: "com.example.not-enabled")

        XCTAssertTrue(switcher.requests.isEmpty)
        XCTAssertEqual(
            controller.selectionFailure,
            InputSourceController.SelectionFailure(sourceID: "com.example.not-enabled", reason: .unknownSource)
        )
    }

    func testSystemRefusalIsReportedWithItsOSStatus() {
        let reader = FakeInputSourceReader(current: abc.id, sources: [abc, pinyin])
        let switcher = FakeInputSourceSwitcher(result: .failed(osStatus: -50)) { _ in }
        let controller = makeController(reader: reader, switcher: switcher)
        controller.start()

        controller.select(id: pinyin.id)

        XCTAssertEqual(
            controller.selectionFailure,
            InputSourceController.SelectionFailure(sourceID: pinyin.id, reason: .systemRefused(osStatus: -50))
        )
        XCTAssertEqual(controller.state.selectedID, abc.id, "the icon must keep drawing the system's truth")
    }

    func testNoErrWithoutAnActualSwitchIsReportedAsNotConfirmed() {
        let reader = FakeInputSourceReader(current: abc.id, sources: [abc, pinyin])
        let switcher = FakeInputSourceSwitcher(result: .selected) { _ in
            // Simulates the known sandbox/FrontApp limitation: noErr, but the
            // system keeps reporting the old source as current.
        }
        let scheduler = FakeInputSourceConfirmationScheduler()
        let controller = makeController(reader: reader, switcher: switcher, scheduler: scheduler)
        controller.start()

        controller.select(id: pinyin.id)
        scheduler.runAllPending()

        XCTAssertEqual(
            controller.selectionFailure,
            InputSourceController.SelectionFailure(sourceID: pinyin.id, reason: .notConfirmed)
        )
        XCTAssertEqual(scheduler.scheduledCount, InputSourceController.confirmationAttempts)
        XCTAssertEqual(controller.state.selectedID, abc.id)
    }

    func testRapidReselectionAbandonsTheStaleConfirmation() {
        let reader = FakeInputSourceReader(current: abc.id, sources: [abc, pinyin])
        let switcher = FakeInputSourceSwitcher(result: .selected) { [reader] id in
            reader.current = id
        }
        let scheduler = FakeInputSourceConfirmationScheduler()
        let controller = makeController(reader: reader, switcher: switcher, scheduler: scheduler)
        controller.start()

        controller.select(id: abc.id)      // stale target
        controller.select(id: pinyin.id)   // live target
        scheduler.runAllPending()

        XCTAssertEqual(controller.state.selectedID, pinyin.id)
        XCTAssertNil(controller.selectionFailure)
    }

    func testRepeatedStartRegistersObserversOnce() {
        let notifications = FakeInputSourceNotifications()
        let controller = makeController(notifications: notifications)

        controller.start()
        controller.start()

        XCTAssertEqual(notifications.observeNames, [
            InputSourceNotifications.selectedSourceChanged,
            InputSourceNotifications.enabledSourcesChanged
        ])
    }

    func testStopRemovesObserversAndClearsFeedback() {
        let reader = FakeInputSourceReader(current: abc.id, sources: [abc])
        let notifications = FakeInputSourceNotifications()
        let scheduler = FakeInputSourceConfirmationScheduler()
        let controller = makeController(reader: reader, notifications: notifications, scheduler: scheduler)
        controller.start()
        controller.select(id: "com.example.missing")
        XCTAssertNotNil(controller.selectionFailure)

        controller.stop()

        XCTAssertEqual(notifications.removedTokens.count, 2)
        XCTAssertNil(controller.selectionFailure)
        scheduler.runAllPending()
    }

    func testStoppedControllerIgnoresLateNotifications() {
        let reader = FakeInputSourceReader(current: abc.id, sources: [abc])
        let notifications = FakeInputSourceNotifications()
        let controller = makeController(reader: reader, notifications: notifications)
        controller.start()
        controller.stop()

        reader.current = pinyin.id
        notifications.emit(InputSourceNotifications.selectedSourceChanged)

        XCTAssertEqual(controller.state.selectedID, abc.id)
    }

    // MARK: - Fixtures

    private func makeController(
        reader: FakeInputSourceReader = FakeInputSourceReader(),
        switcher: FakeInputSourceSwitcher = FakeInputSourceSwitcher(result: .selected) { _ in },
        notifications: FakeInputSourceNotifications = FakeInputSourceNotifications(),
        scheduler: FakeInputSourceConfirmationScheduler = FakeInputSourceConfirmationScheduler()
    ) -> InputSourceController {
        InputSourceController(
            reader: reader,
            switcher: switcher,
            notifications: notifications,
            confirmationScheduler: scheduler
        )
    }
}

private final class FakeInputSourceReader: InputSourceReading {
    var current: String?
    var sources: [RawInputSource]

    init(current: String? = nil, sources: [RawInputSource] = []) {
        self.current = current
        self.sources = sources
    }

    func currentKeyboardInputSourceID() -> String? { current }
    func keyboardInputSources() -> [RawInputSource] { sources }
}

private final class FakeInputSourceSwitcher: InputSourceSwitching {
    var requests: [String] = []
    private let result: InputSourceSelectionResult
    private let onSelect: (String) -> Void

    init(result: InputSourceSelectionResult, onSelect: @escaping (String) -> Void) {
        self.result = result
        self.onSelect = onSelect
    }

    func select(id: String) -> InputSourceSelectionResult {
        requests.append(id)
        onSelect(id)
        return result
    }
}

@MainActor
private final class FakeInputSourceNotifications: InputSourceNotificationObserving {
    private struct Registration {
        let name: Notification.Name
        let token: NSObjectProtocol
        let handler: @MainActor () -> Void
    }

    private(set) var observeNames: [Notification.Name] = []
    private(set) var removedTokens: [NSObjectProtocol] = []
    private var registrations: [Registration] = []

    func observe(
        _ name: Notification.Name,
        handler: @escaping @MainActor () -> Void
    ) -> NSObjectProtocol {
        observeNames.append(name)
        let token: NSObjectProtocol = NSObject()
        registrations.append(Registration(name: name, token: token, handler: handler))
        return token
    }

    func remove(_ token: NSObjectProtocol) {
        removedTokens.append(token)
        registrations.removeAll { $0.token === (token as AnyObject) }
    }

    func emit(_ name: Notification.Name) {
        for registration in registrations where registration.name == name {
            registration.handler()
        }
    }
}

@MainActor
private final class FakeInputSourceConfirmationScheduler: InputSourceConfirmationScheduling {
    private(set) var scheduledCount = 0
    private var pending: [@MainActor () -> Void] = []

    func schedule(after delay: Duration, action: @escaping @MainActor () -> Void) {
        scheduledCount += 1
        pending = [action]
    }

    func cancel() {
        pending = []
    }

    /// Runs the pending confirmation, then every confirmation it schedules in
    /// turn, so a test drives the whole bounded retry loop deterministically.
    func runAllPending() {
        var iterations = 0
        while !pending.isEmpty, iterations < 16 {
            iterations += 1
            let next = pending.removeFirst()
            next()
        }
    }
}
