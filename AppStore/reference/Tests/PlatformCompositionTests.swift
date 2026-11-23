import XCTest
@testable import StatusTrioCore

@MainActor
final class PlatformCompositionTests: XCTestCase {
    func testDirectFactoryKeepsEveryDirectPlatformReader() {
        let factory = DirectPlatformFactory.self

        XCTAssertTrue(factory.chargeLimitProvider() is SystemChargeLimitReader)
        XCTAssertTrue(factory.wifiKnownNetworkProvider() is NetworksetupWiFiKnownNetworkProvider)
        XCTAssertTrue(factory.bluetoothPairedDeviceReader() is SystemProfilerBluetoothPairedDeviceWorker)
        XCTAssertTrue(factory.bluetoothBatteryReader() is SystemProfilerBluetoothBatteryWorker)
        XCTAssertTrue(factory.accessoryBatteryReader() is PmsetAccessoryBatteryWorker)
        XCTAssertTrue(factory.systemPowerReader() is SystemPowerReader)
        XCTAssertTrue(factory.mobileBatteryReader() is MobileBatteryHelperReader)
        XCTAssertTrue(factory.bluetoothRadioBackend() is IOBluetoothRadioPowerBackend)
        XCTAssertTrue(factory.listeningModeBackend() is CoreAudioBluetoothListeningModeBackend)
        XCTAssertTrue(
            factory.listeningModeEndpointProvider()
                is CoreAudioBluetoothListeningModeEndpointProvider
        )
        XCTAssertTrue(
            factory.listeningModeListenerBackend()
                is CoreAudioBluetoothListeningModeListenerBackend
        )
        XCTAssertTrue(factory.lowPowerModeClient() is XPCPrivilegedHelperClient)
    }

    func testDirectFactoryKeepsInternetSharingDetection() {
        XCTAssertTrue(
            DirectPlatformFactory.wifiStatusReader()
                .hasInternetSharingDetector
        )
    }

    func testDirectFactoryKeepsMobileBatteryDiscovery() {
        XCTAssertTrue(
            DirectPlatformFactory.appleDeviceDiscoveryController()
                .mobileBatteryReader is MobileBatteryHelperReader
        )
    }

    func testDirectFactoryRoutesFacadesToSharedDirectManagers() {
        let updater = DirectPlatformFactory.makeUpdater(
            activationPolicy: AppActivationPolicy()
        )
        let helper = DirectPlatformFactory.privilegedHelper()

        XCTAssertTrue(updater.service is UpdaterManager)
        XCTAssertTrue(helper.service is PrivilegedHelperManager)
    }

    func testSafeDefaultsDoNotExposePrivateMutationsOrEventSources() {
        let wifiReader = CoreWLANStatusReader()
        let radioPower = BluetoothRadioPowerController()
        let bluetooth = BluetoothDeviceController()

        XCTAssertFalse(wifiReader.hasInternetSharingDetector)
        XCTAssertFalse(radioPower.canSetPower)
        XCTAssertFalse(bluetooth.hasConnectionEventSource)
        XCTAssertFalse(bluetooth.hasAccessoryBatteryEventSource)
    }

    func testStoreCapabilitiesUseStableReasonIdentifiers() {
        let capabilities = Dictionary(
            uniqueKeysWithValues: PlatformCapabilities.appStore.map {
                ($0.capability, $0)
            }
        )

        XCTAssertEqual(capabilities["updates"]?.availability, .available)
        XCTAssertEqual(
            capabilities["ddc"]?.reason,
            "distribution.private-ddc"
        )
        XCTAssertEqual(
            capabilities["bluetooth.battery-levels"]?.availability,
            .unsupported(reason: "distribution.reader-not-packaged")
        )
        XCTAssertEqual(
            capabilities["mobile-battery.helper"]?.availability,
            CapabilityAvailability.notVerified
        )
        XCTAssertTrue(PlatformCapabilities.direct.isEmpty)
    }

    func testStoreLiveCompositionDeclaresItsDistributionChannel() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "AppStore/Platform/StoreAppEnvironment.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(
            source.contains("distributionChannel: .appStore"),
            "Store composition must not infer its identity from the compile macro fallback"
        )
    }

    func testStoreBluetoothCompositionDisablesUnverifiedDeviceWrites() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "AppStore/Platform/StoreAppEnvironment.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(
            source.contains("allowsDeviceActions: false"),
            "Store must not let an unverified public Bluetooth provider reach an IOBluetooth write"
        )
    }

    func testGlobalPreferencesStayOutsideStoreComposition() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let storeSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "AppStore/Platform/StoreAppEnvironment.swift"
            ),
            encoding: .utf8
        )
        let directSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/StatusTrioCore/Platform/DirectAppEnvironment.swift"
            ),
            encoding: .utf8
        )
        let storeDefaults = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/StatusTrioCore/Store/SystemStatusStore.swift"
            ),
            encoding: .utf8
        )
        let directOnly = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "AppStore/direct-only-sources.txt"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(
            storeSource.contains("volumeFeedback: nil"),
            "Store composition must not construct the global-preference volume player"
        )
        XCTAssertTrue(
            directSource.contains("volumeFeedback: VolumeFeedbackPlayer()"),
            "Direct composition must explicitly retain the system volume feedback player"
        )
        XCTAssertTrue(
            directSource.contains("DirectSystemIconAppearanceReader.current"),
            "Direct composition must explicitly retain the global icon appearance reader"
        )
        XCTAssertFalse(
            storeDefaults.contains("volumeFeedback: (any VolumeFeedbackPlaying)? = VolumeFeedbackPlayer()"),
            "The shared store must not hide a global-preference reader in a default argument"
        )
        XCTAssertTrue(
            directOnly.contains("Sources/StatusTrioCore/Audio/VolumeFeedback.swift"),
            "The concrete volume feedback player must stay outside Store source membership"
        )
        XCTAssertTrue(
            directOnly.contains("Sources/StatusTrioCore/Platform/DirectSystemIconAppearanceReader.swift"),
            "The global icon appearance reader must stay outside Store source membership"
        )
    }

    func testLiveCompositionOwnsAndInjectsOneLaunchAtLoginManager() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/StatusTrioCore/App/AppEnvironment.swift"
            ),
            encoding: .utf8
        )
        let managerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/StatusTrioCore/App/LaunchAtLoginManager.swift"
            ),
            encoding: .utf8
        )
        let controllerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/StatusTrioCore/UI/Settings/SettingsWindowController.swift"
            ),
            encoding: .utf8
        )
        let settingsSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/StatusTrioCore/UI/Settings/SettingsView.swift"
            ),
            encoding: .utf8
        )
        let generalSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/StatusTrioCore/UI/Settings/GeneralSectionView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(
            appSource.contains("let launchAtLogin = LaunchAtLoginManager()"),
            "Live composition must own one process-wide launch-at-login manager"
        )
        XCTAssertTrue(
            appSource.contains("launchAtLogin: launchAtLogin"),
            "Live composition must inject its manager into the Settings controller"
        )
        XCTAssertTrue(
            controllerSource.contains("launchAtLogin: LaunchAtLoginManager,"),
            "SettingsWindowController must require an injected launch-at-login manager"
        )
        XCTAssertTrue(
            controllerSource.contains("launchAtLogin: launchAtLogin"),
            "SettingsWindowController must forward its manager to SettingsView"
        )
        XCTAssertTrue(
            settingsSource.contains("launchAtLogin: LaunchAtLoginManager,"),
            "SettingsView must require an injected launch-at-login manager"
        )
        XCTAssertTrue(
            settingsSource.contains("launchAtLogin: launchAtLogin"),
            "SettingsView must forward its manager to GeneralSectionView"
        )
        XCTAssertTrue(
            generalSource.contains("launchAtLogin: LaunchAtLoginManager,"),
            "GeneralSectionView must require an injected launch-at-login manager"
        )
        XCTAssertFalse(
            managerSource.contains("static let shared = LaunchAtLoginManager()"),
            "Launch-at-login state must not be supplied through a process-wide singleton"
        )
        XCTAssertFalse(
            generalSource.contains("launchAtLogin: LaunchAtLoginManager = .shared"),
            "GeneralSectionView must not hide a process-wide manager default"
        )
    }

    func testStoreCompositionExplicitlyOwnsAppleDeviceDiscovery() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let storeSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "AppStore/Platform/StoreAppEnvironment.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(
            storeSource.contains("appleDeviceDiscovery: AppleDeviceDiscoveryController"),
            "Store makeStore must accept Apple device discovery as a composition input"
        )
        XCTAssertTrue(
            storeSource.range(
                of: #"AppleDeviceDiscoveryController\(\s*reader:\s*UnavailableMobileBatteryReader\(\)\s*\)"#,
                options: .regularExpression
            ) != nil,
            "Store live composition must explicitly use the unavailable mobile battery reader"
        )
        XCTAssertTrue(
            storeSource.contains("appleDeviceDiscovery: appleDeviceDiscovery"),
            "Store makeStore must pass its explicit discovery controller to SystemStatusStore"
        )
    }
}
