import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class PlatformServiceFacadeTests: XCTestCase {
    func testLiveCompositionSharesInjectedServicesAcrossSettingsMenuAndPopover() throws {
        let suite = "PlatformServiceFacadeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.appIconPlacement = .dock
        settings.hasCompletedIconGuideOnboarding = true
        let store = SystemStatusStore(
            batteryMonitor: CompositionBatteryMonitor(),
            wifiMonitor: CompositionWiFiMonitor(),
            volumeMonitor: CompositionVolumeMonitor()
        )
        let updaterService = FakeUpdateService()
        let updater = UpdateStateFacade(service: updaterService)
        let helperService = FakeHelperFacadeService()
        let helper = PrivilegedHelperFacade(service: helperService)
        let environment = AppEnvironment.makeLive(
            settings: settings,
            store: store,
            makeUpdater: { _ in updater },
            privilegedHelper: helper
        )
        defer { environment.stop() }
        let menuAndPopover = environment.statusBarController.platformServicesForTesting
        let preferences = environment.settingsWindowController.platformServicesForTesting

        XCTAssertTrue(menuAndPopover.updater === updater)
        XCTAssertTrue(menuAndPopover.helper === helper)
        XCTAssertTrue(preferences.updater === updater)
        XCTAssertTrue(preferences.helper === helper)

        updaterService.stateSubject.send(UpdateControlState(
            delivery: .direct,
            canCheckForUpdates: true,
            automaticallyChecksForUpdates: false
        ))
        helperService.presentationSubject.send(PrivilegedHelperPresentation(
            availability: .available,
            isEnabled: true,
            requiresApproval: false,
            isReady: true,
            didFailLastOperation: false,
            lastErrorMessage: nil
        ))
        XCTAssertTrue(menuAndPopover.updater.canCheckForUpdates)
        XCTAssertTrue(menuAndPopover.helper.isReady)
        XCTAssertTrue(preferences.updater.canCheckForUpdates)
        XCTAssertTrue(preferences.helper.isReady)
    }

    func testUpdateFacadeReflectsServicePublisherWithoutManualRefresh() {
        let service = FakeUpdateService()
        let facade = UpdateStateFacade(service: service)

        XCTAssertEqual(facade.delivery, .direct)
        XCTAssertFalse(facade.canCheckForUpdates)

        service.stateSubject.send(
            UpdateControlState(
                delivery: .direct,
                canCheckForUpdates: true,
                automaticallyChecksForUpdates: true
            )
        )

        XCTAssertTrue(facade.canCheckForUpdates)
        XCTAssertTrue(facade.automaticallyChecksForUpdates)
    }

    func testSystemManagedUpdateHasNoManualCheckOrAutomaticPreference() {
        let facade = UpdateStateFacade(service: SystemManagedUpdateService())
        var checks = 0
        let cancellable = facade.$state.sink { _ in checks += 1 }

        facade.start()
        facade.checkForUpdates()
        facade.setAutomaticallyChecksForUpdates(true)

        XCTAssertEqual(facade.delivery, .systemManaged)
        XCTAssertFalse(facade.canCheckForUpdates)
        XCTAssertFalse(facade.automaticallyChecksForUpdates)
        XCTAssertEqual(facade.state, .systemManaged)
        XCTAssertGreaterThan(checks, 0)
        withExtendedLifetime(cancellable) {}
    }

    func testHelperFacadeReflectsServicePublisherWithoutManualRefresh() {
        let service = FakeHelperFacadeService()
        let facade = PrivilegedHelperFacade(service: service)

        XCTAssertFalse(facade.isReady)
        service.presentationSubject.send(
            PrivilegedHelperPresentation(
                availability: .available,
                isEnabled: true,
                requiresApproval: false,
                isReady: true,
                didFailLastOperation: false,
                lastErrorMessage: nil
            )
        )

        XCTAssertTrue(facade.isAvailable)
        XCTAssertTrue(facade.isEnabled)
        XCTAssertTrue(facade.isReady)
    }

    func testUnsupportedHelperIsUnavailableAndIgnoresWrites() {
        let facade = PrivilegedHelperFacade(service: UnsupportedPrivilegedHelperService())

        facade.setEnabled(true)

        XCTAssertFalse(facade.isAvailable)
        XCTAssertFalse(facade.isEnabled)
        XCTAssertFalse(facade.presentation.availability.isActionable)
    }
}

@MainActor
private final class CompositionBatteryMonitor: BatteryMonitoring {
    let updates = AsyncStream<BatteryStatus> { _ in }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class CompositionWiFiMonitor: WiFiMonitoring {
    let updates = AsyncStream<WiFiStatus> { _ in }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class CompositionVolumeMonitor: VolumeMonitoring {
    let updates = AsyncStream<VolumeStatus> { _ in }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class FakeUpdateService: UpdateServicing {
    let stateSubject = CurrentValueSubject<UpdateControlState, Never>(
        UpdateControlState(
            delivery: .direct,
            canCheckForUpdates: false,
            automaticallyChecksForUpdates: false
        )
    )

    var state: UpdateControlState { stateSubject.value }
    var statePublisher: AnyPublisher<UpdateControlState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    func start() {}
    func checkForUpdates() {}
    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {}
}

@MainActor
private final class FakeHelperFacadeService: PrivilegedHelperServicingFacade {
    let presentationSubject = CurrentValueSubject<PrivilegedHelperPresentation, Never>(.unsupported)

    var presentation: PrivilegedHelperPresentation { presentationSubject.value }
    var presentationPublisher: AnyPublisher<PrivilegedHelperPresentation, Never> {
        presentationSubject.eraseToAnyPublisher()
    }

    func setEnabled(_ enabled: Bool) {}
    func restoreUserIntent(_ enabled: Bool) {}
    func refresh() {}
    func refreshAfterActivation() {}
    func openLoginItemsSettings() {}
}
