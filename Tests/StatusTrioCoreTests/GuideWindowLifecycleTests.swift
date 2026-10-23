import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class GuideWindowLifecycleTests: XCTestCase {
    func testOnboardingCloseReleasesWindowAndHostingContentAfterDrain() throws {
        let fixture = try DefaultsFixture()
        defer { fixture.tearDown() }
        let application = LifecycleActivationApplication()
        let controller = OnboardingWindowController(
            settings: SettingsStore(defaults: fixture.defaults),
            localization: Localization(
                defaults: fixture.defaults,
                preferredLanguages: ["en"]
            ),
            activationPolicy: AppActivationPolicy(application: application)
        )

        let probes = try showAndCloseProbedWindow(controller: controller)

        XCTAssertNil(controller.window)
        XCTAssertNil(probes.window.value)
        XCTAssertNil(probes.contentView.value)
        XCTAssertNil(probes.contentController.value)
        XCTAssertEqual(application.policies.last, .accessory)
    }

    func testRepeatedOnboardingShowCloseDoesNotAccumulateWindows() throws {
        let fixture = try DefaultsFixture()
        defer { fixture.tearDown() }
        let controller = OnboardingWindowController(
            settings: SettingsStore(defaults: fixture.defaults),
            localization: Localization(
                defaults: fixture.defaults,
                preferredLanguages: ["en"]
            ),
            activationPolicy: AppActivationPolicy(
                application: LifecycleActivationApplication()
            )
        )

        for _ in 0..<5 {
            let probes = try showAndCloseProbedWindow(controller: controller)

            XCTAssertNil(controller.window)
            XCTAssertNil(probes.window.value)
            XCTAssertNil(probes.contentView.value)
            XCTAssertNil(probes.contentController.value)
        }
    }
}

@MainActor
private struct GuideWindowProbes {
    let window: DeinitProbeRef<NSWindow>
    let contentView: DeinitProbeRef<NSView>
    let contentController: DeinitProbeRef<NSViewController>
}

@MainActor
private func showAndCloseProbedWindow(
    controller: OnboardingWindowController
) throws -> GuideWindowProbes {
    let probes = MainActor.assumeIsolated {
        autoreleasepool { () -> GuideWindowProbes in
            controller.show()
            let window = controller.window!
            let contentView = window.contentView!
            let contentController = window.contentViewController!
            let probes = GuideWindowProbes(
                window: DeinitProbe.track(window),
                contentView: DeinitProbe.track(contentView),
                contentController: DeinitProbe.track(contentController)
            )

            window.close()
            drainRunLoop()
            return probes
        }
    }
    XCTAssertNil(controller.window)
    return probes
}

@MainActor
private struct DefaultsFixture {
    let defaults: UserDefaults
    private let suiteName: String

    init() throws {
        suiteName = "StatusTrioCoreTests.GuideWindow.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    func tearDown() {
        defaults.removeTestSuite(named: suiteName)
    }
}

@MainActor
private func drainRunLoop() {
    autoreleasepool {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
}

@MainActor
private final class LifecycleActivationApplication: ApplicationActivationPolicyApplying {
    private(set) var policies: [NSApplication.ActivationPolicy] = []
    private(set) var currentActivationPolicy: NSApplication.ActivationPolicy = .accessory

    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        policies.append(activationPolicy)
        guard currentActivationPolicy != activationPolicy else { return false }
        currentActivationPolicy = activationPolicy
        return true
    }
}
