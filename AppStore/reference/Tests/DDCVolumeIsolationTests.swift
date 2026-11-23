import CoreAudio
import XCTest
@testable import StatusTrioCore

@MainActor
final class DDCVolumeIsolationTests: XCTestCase {
    func testCoordinatorProtocolDeliversUpdateThroughSharedVolumeMonitor() async {
        let output = AudioOutputDevice(
            id: 42,
            name: "External Display",
            uid: "DISPLAY-A",
            isCurrent: true
        )
        let reader = IsolationAudioStatusReader(reading: VolumeReading(
            scalar: nil,
            isMuted: false,
            deviceName: output.name,
            currentDevice: output,
            canSetVolume: false,
            canMute: false
        ), devices: [output])

        var createdCoordinator: IsolationDDCCoordinator?
        let monitor = VolumeMonitor(
            statusReader: reader,
            eventMonitor: IsolationVolumeEvents(),
            ddcCoordinatorFactory: { onUpdate, _ in
                let coordinator = IsolationDDCCoordinator(onUpdate: onUpdate)
                createdCoordinator = coordinator
                return coordinator
            }
        )
        let observation = DDCVolumeStatusObservation()
        observation.start(consuming: monitor.updates)
        await fulfillment(of: [observation.attached], timeout: 2)
        defer {
            monitor.stop()
            observation.stop()
        }
        let statusExpectation = observation.expect("DDC volume is confirmed") {
            $0.scalar == 0.75
        }

        monitor.start()
        await fulfillment(of: [statusExpectation], timeout: 2)

        XCTAssertEqual(createdCoordinator?.selectedUID, output.uid)
        XCTAssertTrue(observation.latestStatus?.canSetVolume == true)
        XCTAssertFalse(observation.latestStatus?.canMute == true)
        XCTAssertEqual(observation.latestStatus?.outputDevices.first?.volume, 0.75)
    }

    func testUnavailableCoordinatorLeavesDDCVolumeUnavailable() async {
        let output = AudioOutputDevice(
            id: 42,
            name: "External Display",
            uid: "DISPLAY-A",
            isCurrent: true
        )
        let reader = IsolationAudioStatusReader(reading: VolumeReading(
            scalar: nil,
            isMuted: false,
            deviceName: output.name,
            currentDevice: output,
            canSetVolume: false,
            canMute: false
        ), devices: [output])
        let coordinator = UnavailableDDCVolumeCoordinator()
        let monitor = VolumeMonitor(
            statusReader: reader,
            eventMonitor: IsolationVolumeEvents(),
            ddcCoordinatorFactory: { _, _ in coordinator }
        )
        let observation = DDCVolumeStatusObservation()
        observation.start(consuming: monitor.updates)
        await fulfillment(of: [observation.attached], timeout: 2)
        defer {
            monitor.stop()
            observation.stop()
        }
        let statusExpectation = observation.expect("DDC volume stays unavailable") {
            $0.scalar == nil && !$0.canSetVolume && !$0.canMute
        }

        monitor.start()
        await fulfillment(of: [statusExpectation], timeout: 2)

        XCTAssertNil(coordinator.setVolume(0.6))
    }

    func testDirectCompatibilityInitializerStillAcceptsInjectedTransport() async {
        let output = AudioOutputDevice(
            id: 42,
            name: "External Display",
            uid: "DISPLAY-A",
            isCurrent: true
        )
        let reader = IsolationAudioStatusReader(reading: VolumeReading(
            scalar: nil,
            isMuted: false,
            deviceName: output.name,
            currentDevice: output,
            canSetVolume: false,
            canMute: false
        ), devices: [output])
        let transport = IsolationReadableDDCTransport()
        let monitor = VolumeMonitor(
            statusReader: reader,
            eventMonitor: IsolationVolumeEvents(),
            ddcTransport: transport
        )
        let observation = DDCVolumeStatusObservation()
        observation.start(consuming: monitor.updates)
        await fulfillment(of: [observation.attached], timeout: 2)
        defer {
            monitor.stop()
            observation.stop()
        }
        let statusExpectation = observation.expect("direct DDC volume is confirmed") {
            $0.scalar == 0.5
        }

        monitor.start()
        await fulfillment(of: [statusExpectation], timeout: 2)

        XCTAssertEqual(transport.resolveCount, 1)
        XCTAssertTrue(observation.latestStatus?.canSetVolume == true)
    }

    func testDirectCoordinatorSatisfiesSharedProtocolBoundary() {
        let coordinator: any DDCVolumeCoordinating = DDCVolumeCoordinator(
            transport: IsolationDDCTransport()
        ) { _ in }

        XCTAssertEqual(coordinator.generation, 0)
        coordinator.stop()
    }

    func testFactoryConfigurationReachesDirectCoordinator() async {
        let output = AudioOutputDevice(
            id: 42,
            name: "External Display",
            uid: "DISPLAY-A",
            isCurrent: true
        )
        let reader = IsolationAudioStatusReader(reading: VolumeReading(
            scalar: nil,
            isMuted: false,
            deviceName: output.name,
            currentDevice: output,
            canSetVolume: false,
            canMute: false
        ), devices: [output])
        let transport = IsolationReadableDDCTransport()
        let factory: DDCVolumeCoordinatorFactory = { onUpdate, configuration in
            DDCVolumeCoordinator(
                transport: transport,
                debounce: configuration.debounce,
                readWatchdog: configuration.readWatchdog,
                beforeReadValidation: configuration.beforeReadValidation,
                onReadCompletion: configuration.onReadCompletion,
                onDebounceSettled: configuration.onDebounceSettled,
                sleep: configuration.sleep,
                onUpdate: onUpdate
            )
        }
        let monitor = VolumeMonitor(
            statusReader: reader,
            eventMonitor: IsolationVolumeEvents(),
            ddcCoordinatorFactory: factory
        )
        let observation = DDCVolumeStatusObservation()
        observation.start(consuming: monitor.updates)
        await fulfillment(of: [observation.attached], timeout: 2)
        defer {
            monitor.stop()
            observation.stop()
        }
        let statusExpectation = observation.expect("factory DDC volume is confirmed") {
            $0.scalar == 0.5
        }

        monitor.start()
        await fulfillment(of: [statusExpectation], timeout: 2)

        XCTAssertEqual(transport.resolveCount, 1)
    }
}

@MainActor
private final class IsolationAudioStatusReader: AudioStatusReadingProviding {
    private let reading: VolumeReading
    private let devices: [AudioOutputDevice]

    init(reading: VolumeReading, devices: [AudioOutputDevice]) {
        self.reading = reading
        self.devices = devices
    }

    func read(
        includeOutputDevices: Bool,
        completion: @escaping @MainActor @Sendable (AudioStatusReading) -> Void
    ) {
        completion(AudioStatusReading(
            volume: reading,
            outputDevices: includeOutputDevices ? devices : nil
        ))
    }
}

@MainActor
private final class IsolationVolumeEvents: VolumeEventMonitoring {
    func start(
        onDefaultDeviceChange: @escaping @MainActor @Sendable () -> Void,
        onVolumeChange: @escaping @MainActor @Sendable () -> Void
    ) {}
    func reconcile() {}
    func recover() {}
    func stop() {}
}

@MainActor
private final class IsolationDDCCoordinator: DDCVolumeCoordinating {
    private let onUpdate: @MainActor (DDCVolumeUpdate) -> Void
    private(set) var generation: UInt64 = 0
    private(set) var selectedUID: String?

    init(onUpdate: @escaping @MainActor (DDCVolumeUpdate) -> Void) {
        self.onUpdate = onUpdate
    }

    func select(outputID: AudioDeviceID, uid: String?) {
        generation &+= 1
        selectedUID = uid
        guard let uid else { return }
        let currentGeneration = generation
        Task { @MainActor in
            onUpdate(DDCVolumeUpdate(
                outputID: outputID,
                uid: uid,
                generation: currentGeneration,
                capability: .readable(DDCVolumeReply(current: 75, maximum: 100)),
                commandID: nil
            ))
        }
    }

    func topologyChanged() {
        generation &+= 1
    }

    func setDetailsVisible(_ visible: Bool) {}
    func setDisplayAsleep(_ asleep: Bool) {}

    func setVolume(_ scalar: Double) -> UInt64? {
        nil
    }

    func flushPendingVolume() {}
    func stop() {}
}

private final class IsolationDDCTransport: DDCVolumeTransport {
    func resolve(uid: String) -> DDCDisplayTarget? {
        nil
    }

    func read(_ target: DDCDisplayTarget) -> DDCVolumeReadResult {
        .failure(.serviceUnavailable)
    }

    func write(_ target: DDCDisplayTarget, value: UInt16) -> Bool {
        false
    }
}

private final class IsolationReadableDDCTransport: DDCVolumeTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var storedResolveCount = 0

    var resolveCount: Int {
        lock.withLock { storedResolveCount }
    }

    func resolve(uid: String) -> DDCDisplayTarget? {
        lock.withLock { storedResolveCount += 1 }
        return DDCDisplayTarget(uid: uid, service: nil)
    }

    func read(_ target: DDCDisplayTarget) -> DDCVolumeReadResult {
        .reply(DDCVolumeReply(current: 50, maximum: 100))
    }

    func write(_ target: DDCDisplayTarget, value: UInt16) -> Bool {
        true
    }
}
