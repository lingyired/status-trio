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
}
