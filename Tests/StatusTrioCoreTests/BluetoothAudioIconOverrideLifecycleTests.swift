import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class BluetoothAudioIconOverrideLifecycleTests: XCTestCase {
    func testLiveDeviceUpdatesPersistenceAndDockAppearanceAcrossRestart() async throws {
        let suiteName = "StatusTrioCoreTests.BluetoothAudioIconOverride.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removeTestSuite(named: suiteName)
        defer { TestUserDefaults.removeSuite(named: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        settings.replacesNetworkIconWithBluetoothAudio = true
        settings.setBluetoothNetworkIconDevice(
            address: "AA:BB:CC:DD:EE:FF",
            symbolName: "headphones"
        )
        let worker = MutableBluetoothDeviceReader(result: .success([makeAirPods(generation: 5)]))
        let stateMonitor = TestBluetoothStateMonitor()
        let controller = BluetoothDeviceController(
            worker: worker,
            stateMonitor: stateMonitor,
            batteryReader: TestBluetoothBatteryReader(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        let synchronizer = BluetoothAudioIconOverrideSynchronizer()
        synchronizer.start(devices: controller, settings: settings)

        var appearances: [StatusIconAppearance] = []
        let cancellable = settings.iconAppearancePublisher.sink { appearances.append($0) }
        defer { cancellable.cancel() }

        controller.activate()
        await waitUntil { controller.devices.first?.airPodsModel == .airPodsGen5 }
        let generationFiveSymbol = BluetoothDeviceRowIcon.symbolName(for: makeAirPods(generation: 5))
        XCTAssertEqual(settings.bluetoothNetworkIconSymbolName, generationFiveSymbol)
        XCTAssertEqual(
            appearances.last?.bluetoothAudioOptions.networkIconSymbolOverride,
            generationFiveSymbol
        )

        var dockCache = DockIconRenderCache()
        let dockKeyForAirPodsFive = dockKey(try XCTUnwrap(appearances.last))
        XCTAssertTrue(dockCache.needsRender(dockKeyForAirPodsFive))
        dockCache.recordSuccessfulRender(dockKeyForAirPodsFive)
        XCTAssertEqual(symbolName(dockKeyForAirPodsFive.scene), generationFiveSymbol)

        worker.setResult(.failed)
        controller.refresh()
        await waitUntil { controller.availability == .failed }
        XCTAssertEqual(settings.bluetoothNetworkIconSymbolName, generationFiveSymbol)

        worker.setResult(.success([]))
        stateMonitor.emit(authorization: .allowed, managerState: .poweredOn)
        await waitUntil { controller.availability == .available && controller.devices.isEmpty }
        XCTAssertEqual(settings.bluetoothNetworkIconSymbolName, generationFiveSymbol)

        synchronizer.stop()
        let keyboard = makeKeyboard()
        worker.setResult(.success([keyboard]))
        stateMonitor.emit(authorization: .allowed, managerState: .poweredOn)
        await waitUntil { controller.devices.first?.kind == .peripheral(.keyboard) }
        XCTAssertEqual(settings.bluetoothNetworkIconSymbolName, generationFiveSymbol)

        synchronizer.start(devices: controller, settings: settings)
        let keyboardSymbol = BluetoothDeviceRowIcon.symbolName(for: keyboard)
        XCTAssertEqual(settings.bluetoothNetworkIconSymbolName, keyboardSymbol)
        let dockKeyForKeyboard = dockKey(try XCTUnwrap(appearances.last))
        XCTAssertNotEqual(dockKeyForKeyboard, dockKeyForAirPodsFive)
        XCTAssertTrue(dockCache.needsRender(dockKeyForKeyboard))

        settings.setBluetoothNetworkIconDevice(address: nil, symbolName: nil)
        XCTAssertNil(settings.bluetoothNetworkIconSymbolName)
        XCTAssertNil(appearances.last?.bluetoothAudioOptions.networkIconSymbolOverride)
        synchronizer.stop()
        controller.deactivate()
    }

    private func makeAirPods(generation: Int) -> BluetoothDevice {
        BluetoothDevice(
            id: "AA:BB:CC:DD:EE:FF",
            name: "Renamed Headphones",
            kind: .audio,
            isConnected: true,
            airPodsModel: generation == 5 ? .airPodsGen5 : .airPodsGen4,
            vendorID: 0x004C,
            productID: generation == 5 ? 0x2030 : 0x201C
        )
    }

    private func makeKeyboard() -> BluetoothDevice {
        BluetoothDevice(
            id: "AA:BB:CC:DD:EE:FF",
            name: "External Keyboard",
            kind: .peripheral(.keyboard),
            isConnected: true
        )
    }

    private func dockKey(_ appearance: StatusIconAppearance) -> DockIconRenderKey {
        let status = MenuBarStatus(
            battery: .placeholder,
            wifi: WiFiStatus(state: .connected, rssi: -50),
            connection: .wifi,
            volume: MenuBarVolumeStatus(scalar: 0.5, isMuted: false, deviceName: "AirPods")
        )
        return DockIconRenderKey(
            scene: makeIconPresentationScene(
                status: status,
                battery: appearance.batteryOptions,
                connection: appearance.connectionOptions,
                volume: appearance.volumeOptions,
                bluetooth: appearance.bluetoothAudioOptions
            ),
            backgroundStyle: .dark,
            pixelLength: DockIconRenderer.pixelSize
        )
    }

    private func symbolName(_ scene: IconSceneState) -> String? {
        guard case let .symbol(symbol) = scene.center,
              case let .symbol(name, _, _) = symbol.source else { return nil }
        return name
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(condition(), "condition did not become true before timeout")
    }
}

@MainActor
private final class TestBluetoothStateMonitor: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus = .allowed

    func start() { emit(authorization: .allowed, managerState: .poweredOn) }
    func stop() {}

    func emit(authorization: BluetoothAuthorizationStatus, managerState: BluetoothManagerState) {
        onStateChange?(authorization, managerState)
    }
}

private final class MutableBluetoothDeviceReader: BluetoothPairedDeviceReading, @unchecked Sendable {
    private let lock = NSLock()
    private var result: BluetoothWorkerResult

    init(result: BluetoothWorkerResult) {
        self.result = result
    }

    func setResult(_ result: BluetoothWorkerResult) {
        lock.withLock { self.result = result }
    }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        let currentResult = lock.withLock { result }
        completion(currentResult)
    }
}

private final class TestBluetoothBatteryReader: BluetoothBatteryReading {
    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]?) -> Void) {
        completion([:])
    }
}
