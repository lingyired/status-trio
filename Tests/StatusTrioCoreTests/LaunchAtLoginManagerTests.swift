import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class LaunchAtLoginManagerTests: XCTestCase {
    func testStatusAndAvailabilityReflectTheService() {
        let enabled = LaunchAtLoginManager(service: FakeLaunchAtLoginService(status: .enabled))
        XCTAssertEqual(enabled.status, .enabled)
        XCTAssertTrue(enabled.isEnabled)
        XCTAssertTrue(enabled.isAvailable)

        let notRegistered = LaunchAtLoginManager(
            service: FakeLaunchAtLoginService(status: .notRegistered)
        )
        XCTAssertFalse(notRegistered.isEnabled)
        XCTAssertTrue(notRegistered.isAvailable)
    }

    func testUnsupportedProcessDisablesTheToggle() {
        let service = FakeLaunchAtLoginService(status: .notRegistered, isSupported: false)
        let manager = LaunchAtLoginManager(service: service)

        XCTAssertFalse(manager.isEnabled)
        XCTAssertFalse(manager.isAvailable)

        manager.setEnabled(true)
        XCTAssertEqual(service.registerCallCount, 0)
    }

    func testSystemNotFoundIsTreatedAsNotRegistered() {
        // macOS answers `notFound` for an app that has never registered a login
        // item. Treating that as a failure greyed out the toggle on first run.
        XCTAssertEqual(SystemLaunchAtLoginService.status(for: .notFound), .notRegistered)
        XCTAssertEqual(SystemLaunchAtLoginService.status(for: .notRegistered), .notRegistered)
        XCTAssertEqual(SystemLaunchAtLoginService.status(for: .enabled), .enabled)
        XCTAssertEqual(
            SystemLaunchAtLoginService.status(for: .requiresApproval),
            .requiresApproval
        )
    }

    func testNotRegisteredStateStillAllowsRegistering() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        let manager = LaunchAtLoginManager(service: service)

        XCTAssertTrue(manager.isAvailable)
        manager.setEnabled(true)
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(manager.status, .enabled)
    }

    func testEnablingRegistersAndPublishesEnabled() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        let manager = LaunchAtLoginManager(service: service)

        manager.setEnabled(true)

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(manager.status, .enabled)
        XCTAssertTrue(manager.isEnabled)
        XCTAssertFalse(manager.didFailLastOperation)
    }

    func testDisablingUnregistersAndPublishesNotRegistered() {
        let service = FakeLaunchAtLoginService(status: .enabled)
        let manager = LaunchAtLoginManager(service: service)

        manager.setEnabled(false)

        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(manager.status, .notRegistered)
        XCTAssertFalse(manager.isEnabled)
    }

    func testRegistrationAwaitingApprovalKeepsToggleOn() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        service.statusAfterRegister = .requiresApproval
        let manager = LaunchAtLoginManager(service: service)

        manager.setEnabled(true)

        XCTAssertEqual(manager.status, .requiresApproval)
        XCTAssertTrue(manager.isEnabled)

        // The registration already exists, so asking again must not re-register.
        manager.setEnabled(true)
        XCTAssertEqual(service.registerCallCount, 1)
    }

    func testDisablingAPendingRegistrationUnregisters() {
        let service = FakeLaunchAtLoginService(status: .requiresApproval)
        let manager = LaunchAtLoginManager(service: service)
        XCTAssertTrue(manager.isEnabled)

        manager.setEnabled(false)

        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(manager.status, .notRegistered)
    }

    func testUnsupportedServiceIgnoresRequests() {
        let service = FakeLaunchAtLoginService(status: .notRegistered, isSupported: false)
        let manager = LaunchAtLoginManager(service: service)

        manager.setEnabled(true)
        manager.setEnabled(false)

        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(manager.status, .notRegistered)
    }

    func testRegistrationFailureIsReportedAndLeavesStatusUnchanged() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        service.registerError = TestFailure.registration
        let manager = LaunchAtLoginManager(service: service)

        manager.setEnabled(true)

        XCTAssertTrue(manager.didFailLastOperation)
        XCTAssertEqual(manager.status, .notRegistered)
        XCTAssertFalse(manager.isEnabled)
    }

    func testUnregistrationFailureIsReportedAndLeavesStatusUnchanged() {
        let service = FakeLaunchAtLoginService(status: .enabled)
        service.unregisterError = TestFailure.unregistration
        let manager = LaunchAtLoginManager(service: service)

        manager.setEnabled(false)

        XCTAssertTrue(manager.didFailLastOperation)
        XCTAssertEqual(manager.status, .enabled)
    }

    func testLaterSuccessfulOperationClearsTheFailureFlag() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        service.registerError = TestFailure.registration
        let manager = LaunchAtLoginManager(service: service)
        manager.setEnabled(true)
        XCTAssertTrue(manager.didFailLastOperation)

        service.registerError = nil
        manager.setEnabled(true)

        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertEqual(manager.status, .enabled)
    }

    func testOpenLoginItemsSettingsIsForwardedToTheService() {
        let service = FakeLaunchAtLoginService(status: .requiresApproval)
        let manager = LaunchAtLoginManager(service: service)

        manager.openLoginItemsSettings()

        XCTAssertEqual(service.openLoginItemsCallCount, 1)
    }

    func testRefreshPicksUpExternalChanges() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        let manager = LaunchAtLoginManager(service: service)

        service.status = .enabled
        manager.refresh()

        XCTAssertEqual(manager.status, .enabled)
    }

    func testRefreshKeepsTheFailureWhileTheItemOnlyAwaitsApproval() {
        // `requiresApproval` is where a rejected `register()` lands too, so it
        // cannot be read as "the system caught up"; only `.enabled` retires the
        // failure banner.
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        service.registerError = TestFailure.registration
        let manager = LaunchAtLoginManager(service: service)
        manager.setEnabled(true)
        XCTAssertTrue(manager.didFailLastOperation)

        service.status = .requiresApproval
        manager.refresh()

        XCTAssertTrue(manager.didFailLastOperation)
        XCTAssertTrue(manager.isEnabled)

        service.status = .enabled
        manager.refresh()

        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertTrue(manager.isEnabled)
    }

    func testRefreshKeepsAFailureThatIsStillUnsettled() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        service.registerError = TestFailure.registration
        let manager = LaunchAtLoginManager(service: service)
        manager.setEnabled(true)
        XCTAssertTrue(manager.didFailLastOperation)

        manager.refresh()

        XCTAssertTrue(manager.didFailLastOperation)
        XCTAssertEqual(manager.status, .notRegistered)
    }

    func testFailedUnregistrationIsClearedOnceTheItemIsGone() {
        let service = FakeLaunchAtLoginService(status: .enabled)
        service.unregisterError = TestFailure.unregistration
        let manager = LaunchAtLoginManager(service: service)
        manager.setEnabled(false)
        XCTAssertTrue(manager.didFailLastOperation)

        service.status = .notRegistered
        manager.refresh()

        XCTAssertFalse(manager.didFailLastOperation)
        XCTAssertFalse(manager.isEnabled)
    }

    func testEnabledBindingReadsAndWritesManagerState() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        let manager = LaunchAtLoginManager(service: service)

        XCTAssertFalse(manager.isEnabledBinding.wrappedValue)

        manager.isEnabledBinding.wrappedValue = true
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertTrue(manager.isEnabledBinding.wrappedValue)
    }

    func testEnabledStatePublishesChangesForObservers() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        let manager = LaunchAtLoginManager(service: service)
        var observed: [Bool] = []
        let cancellable = manager.$status.sink { observed.append($0 == .enabled) }

        manager.setEnabled(true)

        withExtendedLifetime(cancellable) {
            XCTAssertEqual(observed, [false, true])
        }
    }

    private enum TestFailure: Error {
        case registration
        case unregistration
    }
}

@MainActor
private final class FakeLaunchAtLoginService: LaunchAtLoginServicing {
    var status: LaunchAtLoginStatus
    var statusAfterRegister: LaunchAtLoginStatus?
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private(set) var openLoginItemsCallCount = 0
    let isSupported: Bool

    init(status: LaunchAtLoginStatus, isSupported: Bool = true) {
        self.status = status
        self.isSupported = isSupported
    }

    func register() throws {
        registerCallCount += 1
        if let registerError {
            throw registerError
        }
        status = statusAfterRegister ?? .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError {
            throw unregisterError
        }
        status = .notRegistered
    }

    func openLoginItemsSettings() {
        openLoginItemsCallCount += 1
    }
}
