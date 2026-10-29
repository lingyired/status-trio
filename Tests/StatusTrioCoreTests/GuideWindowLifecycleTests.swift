import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class GuideWindowLifecycleTests: XCTestCase {
    func testOnboardingUsesDeterministicHostingSize() throws {
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

        controller.show()
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }

        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size, OnboardingWindowController.contentSize)
        XCTAssertEqual(window.contentView?.frame.size, OnboardingWindowController.contentSize)
        XCTAssertTrue(window.contentView is NSHostingView<LocalizedRootView<IconGuideOnboardingView>>)
        XCTAssertEqual(window.contentView?.intrinsicContentSize, NSSize(width: -1, height: -1))
        XCTAssertEqual(window.contentView?.autoresizingMask, [.width, .height])
    }

    func testOnboardingContentFitsItsFixedWindow() throws {
        let fixture = try DefaultsFixture()
        defer { fixture.tearDown() }
        let settings = SettingsStore(defaults: fixture.defaults)
        XCTAssertEqual(settings.telemetryConsentVersion, 0)

        for language in AppLanguage.allCases {
            let localization = Localization(
                defaults: fixture.defaults,
                preferredLanguages: [language.rawValue]
            )
            for page in [IconGuidePage.anatomy, .states] {
                let view = IconGuideOnboardingView(
                    settings: settings,
                    initialPage: page,
                    onCustomize: {},
                    onDone: {}
                )
                .environmentObject(localization)
                let hostingController = NSHostingController(rootView: view)
                hostingController.sizingOptions = [.preferredContentSize]
                hostingController.view.layoutSubtreeIfNeeded()

                let preferredSize = hostingController.preferredContentSize
                XCTAssertLessThanOrEqual(
                    preferredSize.height,
                    OnboardingWindowController.contentSize.height,
                    "\(language.rawValue) \(page)"
                )
            }
        }
    }

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
        XCTAssertNil(probes.hostingView.value)
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
            XCTAssertNil(probes.hostingView.value)
        }
    }
}

@MainActor
private struct GuideWindowProbes {
    let window: DeinitProbeRef<NSWindow>
    let contentView: DeinitProbeRef<NSView>
    let hostingView: DeinitProbeRef<NSView>
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
            let probes = GuideWindowProbes(
                window: DeinitProbe.track(window),
                contentView: DeinitProbe.track(contentView),
                hostingView: DeinitProbe.track(contentView)
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
