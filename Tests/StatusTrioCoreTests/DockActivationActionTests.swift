import AppKit
import Testing
@testable import StatusTrioCore

struct DockActivationActionTests {
    @Test func nativeComputerUseReopenUsesBackgroundSettingsWithEveryPlacement() {
        let configuration = BackgroundUITestingConfiguration(arguments: ["--background-ui-testing"])
        let event = AppleEventActivation(
            kind: .reopen, sender: .other, senderPID: 3798,
            senderBundleIdentifier: "com.openai.sky.CUAService", eventClass: nil, eventID: nil
        )
        for placement in AppIconPlacement.allCases {
            let result = DockActivationAction.resolve(
                event: event, showsPersistentDockIcon: placement.showsDockIcon,
                backgroundUITesting: configuration
            )
            #if DEBUG
            #expect(result == .openSettings)
            #else
            #expect(result == (placement.showsDockIcon ? .showPopover : .openSettings))
            #endif
            #expect(DockActivationAction.resolve(
                event: event, showsPersistentDockIcon: placement.showsDockIcon
            ) == (placement.showsDockIcon ? .showPopover : .openSettings))
        }
    }

    @Test func backgroundConfigurationDoesNotChangePhysicalDockOrUnknownSenderRoutes() {
        for senderID in ["com.apple.dock", "com.example.launcher", "com.openai.sky.CUAService.fake", ""] {
            let event = AppleEventActivation(
                kind: .reopen, sender: AppleEventSender(bundleIdentifier: senderID), senderPID: nil,
                senderBundleIdentifier: senderID, eventClass: nil, eventID: nil
            )
            #expect(DockActivationAction.resolve(
                event: event, showsPersistentDockIcon: true,
                backgroundUITesting: BackgroundUITestingConfiguration(arguments: ["--background-ui-testing"])
            ) == .showPopover)
        }
        let nonReopen = AppleEventActivation(
            kind: .missing, sender: .other, senderPID: nil,
            senderBundleIdentifier: "com.openai.sky.CUAService", eventClass: nil, eventID: nil
        )
        #expect(DockActivationAction.resolve(
            event: nonReopen, showsPersistentDockIcon: true,
            backgroundUITesting: BackgroundUITestingConfiguration(arguments: ["--background-ui-testing"])
        ) == .none)
    }

    @Test func nativeComputerUseReopenKeepsVisibleOnboardingOnItsOwn() {
        let configuration = BackgroundUITestingConfiguration(arguments: ["--background-ui-testing"])
        let event = AppleEventActivation(
            kind: .reopen, sender: .other, senderPID: 3798,
            senderBundleIdentifier: "com.openai.sky.CUAService", eventClass: nil, eventID: nil
        )

        for placement in AppIconPlacement.allCases {
            let result = DockActivationAction.resolve(
                event: event, showsPersistentDockIcon: placement.showsDockIcon,
                backgroundUITesting: configuration, hasVisibleOnboarding: true
            )
            #if DEBUG
            #expect(result == .none)
            #else
            #expect(result == (placement.showsDockIcon ? .showPopover : .openSettings))
            #endif
        }
    }

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
