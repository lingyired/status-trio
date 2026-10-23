import AppKit
import Testing
@testable import StatusTrioCore

struct DockActivationActionTests {
    @Test func dockAndUnknownReopensRespectPersistentPlacement() {
        for sender in [AppleEventSender.dock, .unknown, .other] {
            for (placement, expected) in [
                (AppIconPlacement.dock, DockActivationAction.showPopover),
                (.both, .showPopover),
                (.menuBar, .openSettings)
            ] {
                #expect(DockActivationAction.resolve(
                    isReopenEvent: true,
                    sender: sender,
                    showsPersistentDockIcon: placement.showsDockIcon
                ) == expected)
            }
        }
    }

    @Test func verifiedSettingsEntrypointsWorkWithEveryPlacement() {
        for sender in [AppleEventSender.finder, .spotlight, .launcher] {
            for placement in AppIconPlacement.allCases {
                #expect(DockActivationAction.resolve(
                    isReopenEvent: true,
                    sender: sender,
                    showsPersistentDockIcon: placement.showsDockIcon
                ) == .openSettings)
            }
        }
    }

    @Test func coldLaunchAndExplicitNonReopenEventsDoNothing() {
        for sender in AppleEventSender.allCases {
            for placement in AppIconPlacement.allCases {
                #expect(DockActivationAction.resolve(
                    isReopenEvent: false,
                    sender: sender,
                    showsPersistentDockIcon: placement.showsDockIcon
                ) == .none)
            }
        }
    }

    @MainActor @Test func temporaryRegularModeDoesNotImplyPersistentDock() {
        let application = DockRoutingActivationApplication()
        let policy = AppActivationPolicy(application: application)
        policy.enterTemporaryRegularMode()
        #expect(policy.isRegularApp)
        #expect(DockActivationAction.resolve(
            isReopenEvent: true,
            sender: .dock,
            showsPersistentDockIcon: AppIconPlacement.menuBar.showsDockIcon
        ) == .openSettings)
        policy.leaveTemporaryRegularMode()
    }
}

@MainActor
private final class DockRoutingActivationApplication: ApplicationActivationPolicyApplying {
    var currentActivationPolicy: NSApplication.ActivationPolicy = .accessory

    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        currentActivationPolicy = activationPolicy
        return true
    }
}
