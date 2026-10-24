import AppKit
import Combine
import Testing
@testable import StatusTrioCore

@MainActor
struct UpdaterManagerTests {
    @Test
    func startUsesTheFactoryConfiguredSharedActivationPolicy() {
        let manager = UpdaterManager.shared
        let application = UpdaterActivationPolicySpy()
        let activationPolicy = AppActivationPolicy(application: application)
        defer { manager.configure(activationPolicy: AppActivationPolicy(application: application)) }

        manager.configure(activationPolicy: activationPolicy)
        manager.start()

        #expect(manager.manualUpdatePresentation?.activationPolicy === activationPolicy)
    }

    @Test
    func settingAutomaticallyChecksForUpdatesPublishesFacadeChange() {
        let manager = UpdaterManager.shared
        let facade = UpdateStateFacade(service: manager)
        let originalValue = manager.automaticallyChecksForUpdates
        defer {
            manager.automaticallyChecksForUpdatesBinding.wrappedValue = originalValue
        }

        var didPublishChange = false
        let cancellable = facade.$state
            .dropFirst()
            .sink { state in
                didPublishChange = state.automaticallyChecksForUpdates == !originalValue
            }
        defer { cancellable.cancel() }

        manager.automaticallyChecksForUpdatesBinding.wrappedValue = !originalValue

        #expect(didPublishChange)
        #expect(facade.automaticallyChecksForUpdates == !originalValue)
        #expect(manager.automaticallyChecksForUpdates == !originalValue)
    }
}

@MainActor
private final class UpdaterActivationPolicySpy: ApplicationActivationPolicyApplying {
    private(set) var currentActivationPolicy: NSApplication.ActivationPolicy = .accessory

    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        currentActivationPolicy = activationPolicy
        return true
    }
}
