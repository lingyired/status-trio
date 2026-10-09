import Combine
import Foundation

typealias IconSceneMapper = @MainActor (
    IconPresentationInputs,
    IconPresentationConfiguration
) -> IconSceneState

typealias IconResolutionMapper = @MainActor @Sendable (
    IconPresentationInputs,
    IconConfigurationV1,
    IconSourceSnapshot
) -> IconResolutionOutput

@MainActor
protocol IconPresentationScheduling: AnyObject {
    func schedule(after delay: Duration, action: @escaping @MainActor () -> Void)
    func cancel()
}

@MainActor
private final class TaskIconPresentationScheduler: IconPresentationScheduling {
    private var task: Task<Void, Never>?

    func schedule(after delay: Duration, action: @escaping @MainActor () -> Void) {
        cancel()
        task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.task = nil
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

struct IconPresentationSettings: Equatable, Sendable {
    let configuration: IconPresentationConfiguration
    let menuBarSize: Double
    let testsChargingEffect: Bool
    var designerConfiguration: IconConfigurationV1? = nil
}

struct IconPresentationOutput: Equatable, Sendable {
    let scene: IconSceneState
    var menuBarTestScene: IconSceneState? = nil
    let menuBarSize: Double
    var trace: IconResolutionTrace = .empty
}

private enum IconHeldSlotState: Sendable {
    case outerRing(OuterRingState)
    case center(CenterState)
    case footer(FooterState)
}

private enum IconHeldSourcePayload: Sendable {
    case airPodsBattery(AirPodsBatteryIconSnapshot)
    case connectedBluetoothDeviceSymbol(String)
}

@MainActor
final class IconPresentationViewModel: ObservableObject {
    static let snapshotDebounceInterval: Duration = .milliseconds(500)

    @Published private(set) var output: IconPresentationOutput

    private let snapshots: AnyPublisher<StatusSnapshot, Never>
    private let preferences: AnyPublisher<IconPresentationSettings, Never>
    private let resolveInputs: @MainActor (StatusSnapshot) -> IconPresentationInputs
    private let mapScene: IconSceneMapper
    private let mapResolution: IconResolutionMapper?
    private let resolveSourceSnapshot: @MainActor @Sendable (StatusSnapshot) -> IconSourceSnapshot
    private let now: @MainActor @Sendable () -> Date
    private let snapshotScheduler: any IconPresentationScheduling
    private let holdExpiryScheduler: any IconPresentationScheduling
    private var snapshotSubscription: AnyCancellable?
    private var preferencesSubscription: AnyCancellable?
    private var latestSnapshot: StatusSnapshot
    private var latestSettings: IconPresentationSettings
    private var receivedSnapshotForStart = false
    private var receivedSettingsForStart = false
    private var synchronizedStart = false
    private var holdPolicies: [String: IconSourceHoldPolicy<Bool>] = [:]
    private var lastGoodSlotStates: [String: IconHeldSlotState] = [:]
    private var lastGoodSourcePayloads: [String: IconHeldSourcePayload] = [:]
    private var holdGeneration = 0

    init(
        snapshot: StatusSnapshot,
        settings: IconPresentationSettings,
        snapshots: AnyPublisher<StatusSnapshot, Never>,
        preferences: AnyPublisher<IconPresentationSettings, Never>,
        resolveInputs: @escaping @MainActor (StatusSnapshot) -> IconPresentationInputs,
        mapScene: @escaping IconSceneMapper = { inputs, configuration in
            IconPresentationMapper.scene(inputs: inputs, configuration: configuration)
        },
        mapResolution: IconResolutionMapper? = nil,
        resolveSourceSnapshot: @escaping @MainActor @Sendable (StatusSnapshot) -> IconSourceSnapshot = { _ in .empty },
        now: @escaping @MainActor @Sendable () -> Date = Date.init,
        snapshotScheduler: any IconPresentationScheduling = TaskIconPresentationScheduler(),
        holdExpiryScheduler: any IconPresentationScheduling = TaskIconPresentationScheduler()
    ) {
        self.snapshots = snapshots
        self.preferences = preferences
        self.resolveInputs = resolveInputs
        self.mapScene = mapScene
        self.mapResolution = mapResolution
        self.resolveSourceSnapshot = resolveSourceSnapshot
        self.now = now
        self.snapshotScheduler = snapshotScheduler
        self.holdExpiryScheduler = holdExpiryScheduler
        self.latestSnapshot = snapshot
        self.latestSettings = settings
        self.output = Self.output(
            snapshot: snapshot,
            settings: settings,
            resolveInputs: resolveInputs,
            mapScene: mapScene,
            mapResolution: mapResolution,
            sources: resolveSourceSnapshot(snapshot)
        )
    }

    func refreshSourceState() {
        guard synchronizedStart else { return }
        snapshotScheduler.cancel()
        publishLatestOutput()
    }

    func start() {
        guard snapshotSubscription == nil, preferencesSubscription == nil else { return }
        receivedSnapshotForStart = false
        receivedSettingsForStart = false
        synchronizedStart = false

        snapshotSubscription = snapshots.sink { [weak self] deliveredSnapshot in
            MainActor.assumeIsolated {
                self?.receive(deliveredSnapshot)
            }
        }
        preferencesSubscription = preferences.sink { [weak self] deliveredSettings in
            MainActor.assumeIsolated {
                self?.receive(deliveredSettings)
            }
        }
    }

    func stop() {
        snapshotScheduler.cancel()
        cancelHoldExpiryAndResetPolicies()
        snapshotSubscription?.cancel()
        preferencesSubscription?.cancel()
        snapshotSubscription = nil
        preferencesSubscription = nil
        receivedSnapshotForStart = false
        receivedSettingsForStart = false
        synchronizedStart = false
    }

    private func receive(_ snapshot: StatusSnapshot) {
        latestSnapshot = snapshot
        if !receivedSnapshotForStart {
            receivedSnapshotForStart = true
            publishWhenStartInputsAreReady()
            return
        }
        guard synchronizedStart else { return }

        snapshotScheduler.schedule(after: Self.snapshotDebounceInterval) { [weak self] in
            self?.publishLatestOutput()
        }
    }

    private func receive(_ settings: IconPresentationSettings) {
        if latestSettings.designerConfiguration?.composition != settings.designerConfiguration?.composition {
            resetHoldPolicies()
        }
        latestSettings = settings
        if !receivedSettingsForStart {
            receivedSettingsForStart = true
            publishWhenStartInputsAreReady()
            return
        }
        guard synchronizedStart else { return }

        snapshotScheduler.cancel()
        publishLatestOutput()
    }

    private func publishWhenStartInputsAreReady() {
        guard receivedSnapshotForStart, receivedSettingsForStart else { return }
        synchronizedStart = true
        snapshotScheduler.cancel()
        publishLatestOutput()
    }

    private func publishLatestOutput() {
        let heldSources = heldSourceSnapshot(for: latestSnapshot, at: now())
        let resolved = Self.output(
            snapshot: latestSnapshot,
            settings: latestSettings,
            resolveInputs: resolveInputs,
            mapScene: mapScene,
            mapResolution: mapResolution,
            sources: heldSources.snapshot
        )
        updateLastGoodSlotStates(from: resolved, rawAvailability: heldSources.rawSnapshot)
        let next = applyingHeldSlotStates(resolved, sourceIDs: heldSources.holdingSourceIDs)
        scheduleHoldExpiry()
        guard output != next else { return }
        output = next
    }

    private func heldSourceSnapshot(
        for snapshot: StatusSnapshot,
        at date: Date
    ) -> (snapshot: IconSourceSnapshot, rawSnapshot: IconSourceSnapshot, holdingSourceIDs: Set<String>) {
        let raw = resolveSourceSnapshot(snapshot)
        holdPolicies = holdPolicies.filter { raw.availability[$0.key] != nil }
        var held: [String: IconSourceAvailability] = [:]
        var holdingSourceIDs: Set<String> = []
        for (sourceID, availability) in raw.availability {
            var policy = holdPolicies[sourceID] ?? IconSourceHoldPolicy<Bool>()
            let result: SourceResult<Bool> = switch availability {
            case .available: .available(true)
            case let .unavailable(reason): .unavailable(reason)
            }
            let value = policy.update(result, sourceID: sourceID, at: date)
            if policy.isHolding { holdingSourceIDs.insert(sourceID) }
            holdPolicies[sourceID] = policy
            switch value {
            case .available: held[sourceID] = .available
            case let .unavailable(reason): held[sourceID] = .unavailable(reason)
            }
        }
        let retainedSourceIDs = Set(raw.availability.compactMap { sourceID, availability in
            if case .available = availability { return sourceID }
            return holdingSourceIDs.contains(sourceID) ? sourceID : nil
        })
        for (sourceID, availability) in raw.availability {
            guard case .available = availability else { continue }
            switch sourceID {
            case RingSource.airPodsBattery.rawValue:
                if let payload = raw.airPodsBattery {
                    lastGoodSourcePayloads[sourceID] = .airPodsBattery(payload)
                } else {
                    lastGoodSourcePayloads.removeValue(forKey: sourceID)
                }
            case CenterSource.connectedBluetoothDevice.rawValue:
                if let payload = raw.connectedBluetoothDeviceSymbol {
                    lastGoodSourcePayloads[sourceID] = .connectedBluetoothDeviceSymbol(payload)
                } else {
                    lastGoodSourcePayloads.removeValue(forKey: sourceID)
                }
            default:
                break
            }
        }
        lastGoodSlotStates = lastGoodSlotStates.filter { retainedSourceIDs.contains($0.key) }
        lastGoodSourcePayloads = lastGoodSourcePayloads.filter { retainedSourceIDs.contains($0.key) }

        let airPodsPayload: AirPodsBatteryIconSnapshot?
        if holdingSourceIDs.contains(RingSource.airPodsBattery.rawValue),
           case let .airPodsBattery(payload)? = lastGoodSourcePayloads[RingSource.airPodsBattery.rawValue] {
            airPodsPayload = payload
        } else {
            airPodsPayload = raw.airPodsBattery
        }
        let connectedDevicePayload: String?
        if holdingSourceIDs.contains(CenterSource.connectedBluetoothDevice.rawValue),
           case let .connectedBluetoothDeviceSymbol(payload)? = lastGoodSourcePayloads[CenterSource.connectedBluetoothDevice.rawValue] {
            connectedDevicePayload = payload
        } else {
            connectedDevicePayload = raw.connectedBluetoothDeviceSymbol
        }
        return (
            IconSourceSnapshot(availability: held, airPodsBattery: airPodsPayload,
                               connectedBluetoothDeviceSymbol: connectedDevicePayload,
                               holdingSourceIDs: holdingSourceIDs),
            raw,
            holdingSourceIDs
        )
    }

    private func updateLastGoodSlotStates(
        from output: IconPresentationOutput,
        rawAvailability: IconSourceSnapshot
    ) {
        for (sourceID, availability) in rawAvailability.availability {
            guard case .available = availability else { continue }
            if output.trace.outerRing.selectedSourceID == sourceID, let state = output.scene.outerRing {
                lastGoodSlotStates[sourceID] = .outerRing(state)
            } else if output.trace.center.selectedSourceID == sourceID, let state = output.scene.center {
                lastGoodSlotStates[sourceID] = .center(state)
            } else if output.trace.footer.selectedSourceID == sourceID, let state = output.scene.footer {
                lastGoodSlotStates[sourceID] = .footer(state)
            }
        }
    }

    private func applyingHeldSlotStates(
        _ output: IconPresentationOutput,
        sourceIDs: Set<String>
    ) -> IconPresentationOutput {
        var outerRing = output.scene.outerRing
        var center = output.scene.center
        var footer = output.scene.footer
        let trace = output.trace
        for sourceID in sourceIDs {
            guard let heldState = lastGoodSlotStates[sourceID] else { continue }
            switch heldState {
            case let .outerRing(state):
                guard trace.outerRing.selectedSourceID == sourceID else { continue }
                outerRing = state
            case let .center(state):
                guard trace.center.selectedSourceID == sourceID else { continue }
                center = state
            case let .footer(state):
                guard trace.footer.selectedSourceID == sourceID else { continue }
                footer = state
            }
        }
        let scene = IconSceneState(outerRing: outerRing, center: center, footer: footer)
        let testScene = output.menuBarTestScene.map {
            IconSceneState(
                outerRing: outerRing == output.scene.outerRing ? $0.outerRing : outerRing,
                center: center == output.scene.center ? $0.center : center,
                footer: footer == output.scene.footer ? $0.footer : footer
            )
        }
        return IconPresentationOutput(scene: scene, menuBarTestScene: testScene,
                                      menuBarSize: output.menuBarSize, trace: trace)
    }

    private func scheduleHoldExpiry() {
        holdExpiryScheduler.cancel()
        holdGeneration &+= 1
        guard let expiry = holdPolicies.values.compactMap(\.expirationDate).min() else { return }
        let generation = holdGeneration
        let milliseconds = max(0, Int((expiry.timeIntervalSince(now()) * 1_000).rounded(.up)))
        holdExpiryScheduler.schedule(after: .milliseconds(milliseconds)) { [weak self] in
            guard let self, self.holdGeneration == generation else { return }
            self.publishLatestOutput()
        }
    }

    private func resetHoldPolicies() {
        holdPolicies.removeAll(keepingCapacity: true)
        lastGoodSlotStates.removeAll(keepingCapacity: true)
        lastGoodSourcePayloads.removeAll(keepingCapacity: true)
        holdGeneration &+= 1
        holdExpiryScheduler.cancel()
    }

    private func cancelHoldExpiryAndResetPolicies() {
        holdExpiryScheduler.cancel()
        resetHoldPolicies()
    }

    private static func output(
        snapshot: StatusSnapshot,
        settings: IconPresentationSettings,
        resolveInputs: @MainActor (StatusSnapshot) -> IconPresentationInputs,
        mapScene: IconSceneMapper,
        mapResolution: IconResolutionMapper?,
        sources: IconSourceSnapshot
    ) -> IconPresentationOutput {
        func resolve(_ snapshot: StatusSnapshot) -> IconResolutionOutput {
            let inputs = resolveInputs(snapshot)
            if let designerConfiguration = settings.designerConfiguration, let mapResolution {
                return mapResolution(inputs, designerConfiguration, sources)
            }
            return IconResolutionOutput(
                scene: mapScene(inputs, settings.configuration),
                trace: .empty
            )
        }

        let resolution = resolve(snapshot)
        let menuBarTestScene: IconSceneState?
        if settings.testsChargingEffect {
            let projected = ChargingEffectTestMode.snapshot(snapshot, enabled: true)
            menuBarTestScene = resolve(projected).scene
        } else {
            menuBarTestScene = nil
        }
        return IconPresentationOutput(
            scene: resolution.scene,
            menuBarTestScene: menuBarTestScene,
            menuBarSize: settings.menuBarSize,
            trace: resolution.trace
        )
    }
}
