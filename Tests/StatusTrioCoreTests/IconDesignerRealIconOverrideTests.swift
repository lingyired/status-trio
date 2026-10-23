import AppKit
import Combine
import Foundation
import Testing
@testable import StatusTrioCore

@Suite("Icon designer real icon override")
@MainActor
struct IconDesignerRealIconOverrideTests {
    @Test func simulatedSamplesReplaceAndImmediatelyRestoreTheRealPresentation() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let realScene = fixture.model.output.scene

        fixture.session.mode = .simulated
        fixture.session.setMacBatteryPercentage(9)
        fixture.session.setAppliesToRealIcons(true)

        let simulated = try #require(fixture.model.output.scene.outerRing)
        #expect(simulated.segments.first?.progress == 0.09)
        #expect(fixture.model.output.scene != realScene)
        #expect(fixture.model.output.menuBarSize == fixture.presentationSettings.menuBarSize)

        fixture.session.setAppliesToRealIcons(false)
        #expect(fixture.model.output.scene == realScene)
    }

    @Test func switchingBackToLiveOrChangingSettingsRefreshesTheOverride() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.session.mode = .simulated
        fixture.session.setAppliesToRealIcons(true)
        #expect(fixture.model.output.trace.outerRing.role == .primary)

        fixture.session.setMacBatteryPercentage(33)
        #expect(fixture.model.output.scene.outerRing?.segments.first?.progress == 0.33)

        fixture.settings.updateIconConfiguration {
            $0.appearance.outerRing.strokeScale = 1.5
        }
        #expect(fixture.settings.iconConfiguration.appearance.outerRing.strokeScale == 1.5)

        fixture.session.mode = .live
        #expect(!fixture.session.appliesToRealIcons)
        #expect(fixture.model.output.scene.outerRing?.segments.first?.progress != 0.33)
    }

    @Test func dockAndMenuBarConsumeTheSameOverrideOutput() async throws {
        let fixture = try Fixture(initialPlacement: .both)
        defer { fixture.cleanUp() }
        var menuBarScenes: [IconSceneState] = []
        let menuBar = StatusBarController(
            store: fixture.store,
            settings: fixture.settings,
            iconPresentation: fixture.model,
            localization: Localization(preferredLanguages: ["en"]),
            openSettings: {},
            quitAction: {},
            renderMenuBarIcon: { scene, _, _, _, _ in
                menuBarScenes.append(scene)
                return StatusIconRenderer.MenuBarLayers(base: NSImage(size: NSSize(width: 32, height: 32)))
            }
        )
        defer { menuBar.setVisible(false) }
        fixture.appIconController.start()
        menuBar.flushPendingPresentationForTesting()

        fixture.session.mode = .simulated
        fixture.session.setNetworkRSSI(-100)
        fixture.session.setAppliesToRealIcons(true)
        menuBar.flushPendingPresentationForTesting()
        fixture.appIconController.flushPendingPresentationForTesting()

        try await waitUntil {
            menuBarScenes.last == fixture.model.output.scene
                && fixture.applicationLog.scenes.last == fixture.model.output.scene
        }
        #expect(fixture.model.output.scene.center != nil)
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Timed out waiting for both real icon surfaces to consume the override")
    }

    @MainActor
    private struct Fixture {
        let suiteName: String
        let defaults: UserDefaults
        let settings: SettingsStore
        let store: SystemStatusStore
        let model: IconPresentationViewModel
        let session: IconDesignerPreviewSession
        let bridge: IconDesignerRealIconOverrideBridge
        let presentationSettings: IconPresentationSettings
        let applicationLog: AppIconEventLog
        let appIconController: AppIconController
        private let snapshots: CurrentValueSubject<StatusSnapshot, Never>
        private let preferences: CurrentValueSubject<IconPresentationSettings, Never>
        private let preferenceCancellable: AnyCancellable
        private let application: AppIconApplicationSpy
        private let activationPolicy: AppActivationPolicy
        private let battery = ControllableBatteryMonitor()
        private let wifi = AppIconControllableWiFiMonitor()
        private let volume = AppIconControllableVolumeMonitor()

        init(initialPlacement: AppIconPlacement = .menuBar) throws {
            suiteName = "StatusTrioCoreTests.RealIconOverride.\(UUID().uuidString)"
            defaults = try #require(UserDefaults(suiteName: suiteName))
            defaults.removePersistentDomain(forName: suiteName)
            settings = SettingsStore(defaults: defaults)
            settings.appIconPlacement = initialPlacement
            var configuration = IconConfigurationV1.classic
            configuration.composition.outerRing = SlotSelection(primary: .systemBattery)
            configuration.composition.center = SlotSelection(primary: .network)
            settings.updateIconConfiguration { $0 = configuration }

            let snapshots = CurrentValueSubject<StatusSnapshot, Never>(
                StatusSnapshot(
                    battery: BatteryStatus(
                        rawPercentage: 91,
                        isPresent: true,
                        isCharging: false,
                        isLowPowerMode: false,
                        isConnectedToPower: false
                    ),
                    wifi: WiFiStatus(state: .connected, rssi: -48),
                    connection: .wifi,
                    volume: .placeholder
                )
            )
            self.snapshots = snapshots
            var initialSettings: IconPresentationSettings?
            let initialCancellable = settings.iconPresentationPublisher.sink {
                initialSettings = $0
            }
            let presentationSettings = try #require(initialSettings)
            initialCancellable.cancel()
            self.presentationSettings = presentationSettings
            let preferences = CurrentValueSubject<IconPresentationSettings, Never>(presentationSettings)
            self.preferences = preferences
            model = IconPresentationViewModel(
                snapshot: snapshots.value,
                settings: presentationSettings,
                snapshots: snapshots.eraseToAnyPublisher(),
                preferences: preferences.eraseToAnyPublisher(),
                resolveInputs: { IconPresentationResourceResolver.inputs(snapshot: $0) },
                mapResolution: { inputs, configuration, sources in
                    IconCompositionResolver.resolve(
                        inputs: IconResolutionInputs(system: inputs, sources: sources),
                        configuration: configuration
                    )
                },
                resolveSourceSnapshot: { _ in .empty }
            )
            let preferenceCancellable = settings.iconPresentationPublisher.sink {
                preferences.send($0)
            }
            self.preferenceCancellable = preferenceCancellable
            model.start()

            store = SystemStatusStore(
                batteryMonitor: battery,
                wifiMonitor: wifi,
                volumeMonitor: volume,
                refreshInterval: .seconds(60),
                initialSnapshot: snapshots.value
            )
            session = IconDesignerPreviewSession()
            bridge = IconDesignerRealIconOverrideBridge(
                session: session,
                settings: settings,
                iconPresentation: model
            )
            bridge.start()

            applicationLog = AppIconEventLog()
            application = AppIconApplicationSpy(
                log: applicationLog,
                acceptsActivationPolicy: true
            )
            activationPolicy = AppActivationPolicy(application: application)
            let applicationLog = self.applicationLog
            appIconController = AppIconController(
                settings: settings,
                iconPresentation: model,
                activationPolicy: activationPolicy,
                application: application,
                setMenuBarVisible: { _ in },
                renderDockIcon: { scene, _, _ in
                    applicationLog.scenes.append(scene)
                    return NSImage(size: NSSize(width: 128, height: 128))
                },
                theme: { .default },
                isDarkAppearance: { false },
                notificationCenter: NotificationCenter()
            )
        }

        func cleanUp() {
            bridge.stop()
            appIconController.stop()
            model.stop()
            store.stop()
            preferenceCancellable.cancel()
            TestUserDefaults.removeSuite(named: suiteName)
        }
    }
}
