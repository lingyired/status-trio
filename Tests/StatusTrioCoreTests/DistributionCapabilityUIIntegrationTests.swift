import AppKit
import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class DistributionCapabilityUIIntegrationTests: XCTestCase {
    func testStorePolicyPreventsSyntheticAppleListeningModePreview() {
        withDefaults { defaults in
            let settings = SettingsStore(defaults: defaults)
            settings.previewsBluetoothListeningMode = true
            settings.bluetoothListeningModePreviewDeviceCount = 2

            let listeningModes = BluetoothListeningModeController(
                hal: BluetoothListeningModeHAL(
                    backend: UnavailableBluetoothListeningModeBackend()
                )
            )
            let statusStore = makeStatusStore(listeningModes: listeningModes)
            defer { statusStore.stop() }
            let actions = StatusPanelActions(
                store: statusStore,
                settings: settings,
                capabilityPolicy: .runtimeDefault(for: .appStore)
            )

            statusStore.setPopoverVisible(true)
            actions.volumeListAppeared()

            XCTAssertFalse(
                listeningModes.previewMode,
                "a Store build must not enter the private Apple listening-mode preview path"
            )
            XCTAssertTrue(
                listeningModes.presentations.isEmpty,
                "blocked preview settings must not synthesize Bluetooth rows"
            )
        }
    }

    func testDirectPolicyStillAllowsSyntheticAppleListeningModePreview() {
        withDefaults { defaults in
            let settings = SettingsStore(defaults: defaults)
            settings.previewsBluetoothListeningMode = true
            settings.bluetoothListeningModePreviewDeviceCount = 2

            let listeningModes = BluetoothListeningModeController(
                hal: BluetoothListeningModeHAL(
                    backend: UnavailableBluetoothListeningModeBackend()
                )
            )
            let statusStore = makeStatusStore(listeningModes: listeningModes)
            defer { statusStore.stop() }
            let actions = StatusPanelActions(
                store: statusStore,
                settings: settings,
                capabilityPolicy: .runtimeDefault(for: .direct)
            )

            statusStore.setPopoverVisible(true)
            actions.volumeListAppeared()

            XCTAssertTrue(listeningModes.previewMode)
            XCTAssertEqual(listeningModes.presentations.count, 2)
        }
    }

    func testStorePanelDataSourceSuppressesSyntheticListeningModeRowsAndTaskIdentity() {
        withDefaults { defaults in
            let settings = SettingsStore(defaults: defaults)
            settings.previewsBluetoothListeningMode = true
            settings.bluetoothListeningModePreviewDeviceCount = 2

            let listeningModes = BluetoothListeningModeController(
                hal: BluetoothListeningModeHAL(
                    backend: UnavailableBluetoothListeningModeBackend()
                )
            )
            let statusStore = makeStatusStore(listeningModes: listeningModes)
            defer { statusStore.stop() }
            let directPanel = StatusPanelViewModel(
                store: statusStore,
                settings: settings,
                localization: Localization(
                    defaults: defaults,
                    preferredLanguages: ["en"]
                ),
                actions: StatusPanelActions(
                    store: statusStore,
                    settings: settings,
                    capabilityPolicy: .runtimeDefault(for: .direct)
                ),
                capabilityPolicy: .runtimeDefault(for: .direct)
            )
            defer { directPanel.stop() }

            XCTAssertFalse(directPanel.volume.previewRows.isEmpty)
            XCTAssertTrue(directPanel.volume.listeningModeTaskID.contains("|preview"))

            let storePanel = StatusPanelViewModel(
                store: statusStore,
                settings: settings,
                localization: Localization(
                    defaults: defaults,
                    preferredLanguages: ["en"]
                ),
                actions: StatusPanelActions(
                    store: statusStore,
                    settings: settings,
                    capabilityPolicy: .runtimeDefault(for: .appStore)
                ),
                capabilityPolicy: .runtimeDefault(for: .appStore)
            )
            defer { storePanel.stop() }

            XCTAssertTrue(storePanel.volume.previewRows.isEmpty)
            XCTAssertFalse(storePanel.volume.listeningModeTaskID.contains("|preview"))
        }
    }

    func testNetworkPresentationExcludesUnsupportedInternetSharingOptionOnlyInStore() {
        XCTAssertTrue(
            NetworkSectionPresentation(
                capabilityPolicy: .runtimeDefault(for: .direct)
            ).showsInternetSharingIconOption
        )
        XCTAssertFalse(
            NetworkSectionPresentation(
                capabilityPolicy: .runtimeDefault(for: .appStore)
            ).showsInternetSharingIconOption
        )
    }

    func testStorePolicySkipsHelperRefreshWhenSettingsOpens() {
        withDefaults { defaults in
            let helperService = DistributionHelperServiceSpy(
                presentation: .availableForTesting
            )
            let controller = makeSettingsWindowController(
                defaults: defaults,
                helperService: helperService,
                capabilityPolicy: .runtimeDefault(for: .appStore)
            )

            controller.show()
            defer { controller.window?.close() }

            XCTAssertEqual(
                helperService.refreshCount,
                0,
                "opening Settings must not probe a helper excluded from the Store build"
            )
        }
    }

    func testDirectPolicyStillRefreshesReadyHelperWhenSettingsOpens() {
        withDefaults { defaults in
            let helperService = DistributionHelperServiceSpy(
                presentation: .availableForTesting
            )
            let controller = makeSettingsWindowController(
                defaults: defaults,
                helperService: helperService,
                capabilityPolicy: .runtimeDefault(for: .direct)
            )

            controller.show()
            defer { controller.window?.close() }

            XCTAssertEqual(
                helperService.refreshCount,
                1,
                "the Direct distribution keeps its existing helper refresh behavior"
            )
        }
    }

    func testGeneralPresentationShowsAnalyticsOnlyForDirect() {
        XCTAssertTrue(
            GeneralSectionPresentation(channel: .direct).showsAnalyticsGroup
        )
        XCTAssertFalse(
            GeneralSectionPresentation(channel: .appStore).showsAnalyticsGroup,
            "Store telemetry is ineligible; its General pane must not offer a dead consent toggle"
        )
    }

    func testStoreGeneralSourceHasNoAnalyticsGroupAndDirectKeepsIt() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/StatusTrioCore/UI/Settings/GeneralSectionView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(
            source.contains("if presentation.showsAnalyticsGroup"),
            "the analytics group must be conditionally inserted, not merely disabled"
        )
        XCTAssertTrue(source.contains("analyticsGroup"))
        XCTAssertFalse(
            source.contains("analyticsGroup.disabled"),
            "a disabled Store toggle would still disclose and persist consent"
        )
    }

    func testAboutFooterUsesCardInsetOnlyOnce() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/StatusTrioCore/UI/Settings/AboutSectionView.swift"
            ),
            encoding: .utf8
        )
        let footerStart = try XCTUnwrap(source.range(of: "private var distributionFooter"))
        let footer = source[footerStart.lowerBound...]
        let nextType = footer.range(of: "\nstruct AboutActionsView")
        let footerSource = String(
            footer[..<(nextType?.lowerBound ?? footer.endIndex)]
        )

        XCTAssertEqual(
            footerSource.components(separatedBy: ".padding(.horizontal").count - 1,
            0,
            "the parent card already applies the standard horizontal inset"
        )
        XCTAssertTrue(
            footerSource.contains("Link(destination: AppMetadata.repositoryURL)"),
            "the low-emphasis GitHub project link must remain available"
        )
        XCTAssertFalse(footerSource.lowercased().contains("upgrade"))
        XCTAssertFalse(footerSource.lowercased().contains("purchase"))
    }

    func testLiveCompositionUsesExplicitPolicyAcrossAllSharedSurfaces() throws {
        let suite = "DistributionUI.Live.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.appIconPlacement = .dock
        settings.hasCompletedIconGuideOnboarding = true
        let store = makeStatusStore()
        let updaterService = DistributionUpdateServiceSpy()
        let updater = UpdateStateFacade(service: updaterService)
        let helperService = DistributionHelperServiceSpy(
            presentation: .unsupported
        )
        let helper = PrivilegedHelperFacade(service: helperService)
        let policy = DistributionCapabilityPolicy(
            channel: .appStore,
            records: PlatformCapabilities.appStore
        )

        let environment = AppEnvironment.makeLive(
            settings: settings,
            store: store,
            makeUpdater: { _ in updater },
            privilegedHelper: helper,
            platformCapabilities: PlatformCapabilities.appStore,
            distributionChannel: .appStore
        )
        defer { environment.stop() }

        XCTAssertEqual(environment.capabilityPolicy, policy)
        XCTAssertEqual(
            environment.statusBarController.distributionCapabilityPolicyForTesting,
            policy
        )
        XCTAssertEqual(
            environment.statusBarController.panelCapabilityPolicyForTesting,
            policy
        )
        XCTAssertEqual(
            environment.settingsWindowController.distributionCapabilityPolicyForTesting,
            policy
        )
        XCTAssertTrue(environment.statusBarController.platformServicesForTesting.updater === updater)
        XCTAssertTrue(environment.statusBarController.platformServicesForTesting.helper === helper)
        XCTAssertTrue(environment.settingsWindowController.platformServicesForTesting.updater === updater)
        XCTAssertTrue(environment.settingsWindowController.platformServicesForTesting.helper === helper)
    }

    func testDefaultEnvironmentCompositionResolvesChannelContract() throws {
        let suite = "DistributionUI.Default.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let store = makeStatusStore()
        let environment = makeEnvironment(
            settings: settings,
            store: store,
            defaults: defaults,
            distributionChannel: .appStore
        )
        defer { environment.stop() }

        XCTAssertTrue(
            environment.capabilityPolicy.blocksControl(.privilegedHelper)
        )
        XCTAssertEqual(
            environment.capabilityPolicy,
            .runtimeDefault(for: .appStore)
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "StatusTrioCoreTests.DistributionUI.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("could not create isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }

    private func makeSettingsWindowController(
        defaults: UserDefaults,
        helperService: DistributionHelperServiceSpy,
        capabilityPolicy: DistributionCapabilityPolicy
    ) -> SettingsWindowController {
        SettingsWindowController(
            store: SettingsStore(defaults: defaults),
            statusStore: makeStatusStore(),
            localization: Localization(
                defaults: defaults,
                preferredLanguages: ["en"]
            ),
            activationPolicy: AppActivationPolicy(
                application: DistributionActivationPolicyApplicationSpy()
            ),
            showIconGuide: {},
            helper: PrivilegedHelperFacade(service: helperService),
            capabilityPolicy: capabilityPolicy
        )
    }

    private func makeStatusStore(
        listeningModes: BluetoothListeningModeController? = nil
    ) -> SystemStatusStore {
        if let listeningModes {
            return SystemStatusStore(
                batteryMonitor: DistributionBatteryMonitorStub(),
                wifiMonitor: DistributionWiFiMonitorStub(),
                volumeMonitor: DistributionVolumeMonitorStub(),
                bluetoothListeningModes: listeningModes
            )
        }
        return SystemStatusStore(
            batteryMonitor: DistributionBatteryMonitorStub(),
            wifiMonitor: DistributionWiFiMonitorStub(),
            volumeMonitor: DistributionVolumeMonitorStub()
        )
    }

    private func makeEnvironment(
        settings: SettingsStore,
        store: SystemStatusStore,
        defaults: UserDefaults,
        distributionChannel: DistributionChannel
    ) -> AppEnvironment {
        let localization = Localization(
            defaults: defaults,
            preferredLanguages: ["en"]
        )
        let clock = ChargingEffectClock()
        let application = DistributionActivationPolicyApplicationSpy()
        let activationPolicy = AppActivationPolicy(application: application)
        let iconPresentation = makeTestIconPresentation(
            store: store,
            settings: settings
        )
        let statusBar = StatusBarController(
            store: store,
            settings: settings,
            iconPresentation: iconPresentation,
            localization: localization,
            isVisible: false,
            openSettings: {},
            quitAction: {},
            chargingEffectClock: clock,
            renderMenuBarBase: { _, _, _, _ in nil },
            renderMenuBarOverlay: { _, _, _, _, _ in nil }
        )
        let settingsWindow = SettingsWindowController(
            store: settings,
            statusStore: store,
            localization: localization,
            activationPolicy: activationPolicy,
            showIconGuide: {},
            chargingEffectClock: clock
        )
        let onboarding = OnboardingWindowController(
            settings: settings,
            localization: localization,
            activationPolicy: activationPolicy
        )
        return AppEnvironment(
            store: store,
            settings: settings,
            localization: localization,
            iconPresentation: iconPresentation,
            statusBarController: statusBar,
            settingsWindowController: settingsWindow,
            onboardingWindowController: onboarding,
            activationPolicy: activationPolicy,
            appIconController: AppIconController(
                settings: settings,
                iconPresentation: iconPresentation,
                activationPolicy: activationPolicy,
                application: application,
                setMenuBarVisible: { _ in },
                renderDockIcon: { _, _, _ in nil },
                theme: { .default },
                isDarkAppearance: { false },
                notificationCenter: NotificationCenter()
            ),
            mainMenuController: MainMenuController(
                activationPolicy: activationPolicy,
                localization: localization,
                notificationCenter: NotificationCenter(),
                openSettings: {}
            ),
            inputSourceController: InputSourceController(),
            chargingEffectClock: clock,
            chargingEffectMotionMonitor: ChargingEffectMotionMonitor(
                readReduceMotion: { false },
                notificationCenter: NotificationCenter()
            ),
            telemetryReporter: DistributionTelemetryReporterStub(),
            distributionChannel: distributionChannel
        )
    }
}

private extension PrivilegedHelperPresentation {
    static let availableForTesting = PrivilegedHelperPresentation(
        availability: .available,
        isEnabled: false,
        requiresApproval: false,
        isReady: true,
        didFailLastOperation: false,
        lastErrorMessage: nil
    )
}

@MainActor
private final class DistributionHelperServiceSpy: PrivilegedHelperServicingFacade {
    let presentation: PrivilegedHelperPresentation
    private(set) var refreshCount = 0

    var presentationPublisher: AnyPublisher<PrivilegedHelperPresentation, Never> {
        Just(presentation).eraseToAnyPublisher()
    }

    init(presentation: PrivilegedHelperPresentation) {
        self.presentation = presentation
    }

    func setEnabled(_ enabled: Bool) {}
    func restoreUserIntent(_ enabled: Bool) {}

    func refresh() {
        refreshCount += 1
    }

    func refreshAfterActivation() {}
    func openLoginItemsSettings() {}
}

@MainActor
private final class DistributionActivationPolicyApplicationSpy:
    ApplicationActivationPolicyApplying,
    ApplicationDockIconApplying
{
    private(set) var currentActivationPolicy: NSApplication.ActivationPolicy = .accessory

    func setActivationPolicy(
        _ activationPolicy: NSApplication.ActivationPolicy
    ) -> Bool {
        guard currentActivationPolicy != activationPolicy else { return false }
        currentActivationPolicy = activationPolicy
        return true
    }

    func setApplicationIconImage(_ image: NSImage?) {}
}

@MainActor
private final class DistributionTelemetryReporterStub: TelemetryReporting {
    func start() {}
    func stop() {}
}

@MainActor
private final class DistributionUpdateServiceSpy: UpdateServicing {
    var state: UpdateControlState = .systemManaged
    var statePublisher: AnyPublisher<UpdateControlState, Never> {
        Just(state).eraseToAnyPublisher()
    }

    func start() {}
    func checkForUpdates() {}
    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {}
}

@MainActor
private final class DistributionBatteryMonitorStub: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>

    init() {
        (updates, _) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class DistributionWiFiMonitorStub: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>

    init() {
        (updates, _) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class DistributionVolumeMonitorStub: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>

    init() {
        (updates, _) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}
