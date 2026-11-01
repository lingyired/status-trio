import Combine
import Foundation

typealias IconSceneMapper = @MainActor (
    IconPresentationInputs,
    IconPresentationConfiguration
) -> IconSceneState

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
}

struct IconPresentationOutput: Equatable, Sendable {
    let scene: IconSceneState
    var menuBarTestScene: IconSceneState? = nil
    let menuBarSize: Double
}

@MainActor
final class IconPresentationViewModel: ObservableObject {
    static let snapshotDebounceInterval: Duration = .milliseconds(500)

    @Published private(set) var output: IconPresentationOutput

    private let snapshots: AnyPublisher<StatusSnapshot, Never>
    private let preferences: AnyPublisher<IconPresentationSettings, Never>
    private let inputSources: AnyPublisher<InputSourceDescriptor?, Never>
    private let systemPowers: AnyPublisher<SystemPowerSample?, Never>
    private let resolveInputs: @MainActor (StatusSnapshot) -> IconPresentationInputs
    private let mapScene: IconSceneMapper
    private let snapshotScheduler: any IconPresentationScheduling
    private var snapshotSubscription: AnyCancellable?
    private var preferencesSubscription: AnyCancellable?
    private var inputSourcesSubscription: AnyCancellable?
    private var systemPowersSubscription: AnyCancellable?
    private var latestSnapshot: StatusSnapshot
    private var latestSettings: IconPresentationSettings
    private var latestInputSource: InputSourceDescriptor?
    private var latestSystemPower: SystemPowerSample?
    private var receivedSnapshotForStart = false
    private var receivedSettingsForStart = false
    private var receivedInputSourceForStart = false
    private var synchronizedStart = false

    init(
        snapshot: StatusSnapshot,
        settings: IconPresentationSettings,
        snapshots: AnyPublisher<StatusSnapshot, Never>,
        preferences: AnyPublisher<IconPresentationSettings, Never>,
        inputSources: AnyPublisher<InputSourceDescriptor?, Never> = Empty<InputSourceDescriptor?, Never>().eraseToAnyPublisher(),
        systemPowers: AnyPublisher<SystemPowerSample?, Never> = Empty<SystemPowerSample?, Never>().eraseToAnyPublisher(),
        resolveInputs: @escaping @MainActor (StatusSnapshot) -> IconPresentationInputs,
        mapScene: @escaping IconSceneMapper = { inputs, configuration in
            IconPresentationMapper.scene(inputs: inputs, configuration: configuration)
        },
        snapshotScheduler: any IconPresentationScheduling = TaskIconPresentationScheduler()
    ) {
        self.snapshots = snapshots
        self.preferences = preferences
        self.inputSources = inputSources
        self.systemPowers = systemPowers
        self.resolveInputs = resolveInputs
        self.mapScene = mapScene
        self.snapshotScheduler = snapshotScheduler
        self.latestSnapshot = snapshot
        self.latestSettings = settings
        self.output = Self.output(
            snapshot: snapshot,
            settings: settings,
            inputSource: nil,
            systemPower: nil,
            resolveInputs: resolveInputs,
            mapScene: mapScene
        )
    }

    func start() {
        guard snapshotSubscription == nil, preferencesSubscription == nil else { return }
        receivedSnapshotForStart = false
        receivedSettingsForStart = false
        receivedInputSourceForStart = false
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
        inputSourcesSubscription = inputSources.sink { [weak self] deliveredInputSource in
            MainActor.assumeIsolated {
                self?.receive(deliveredInputSource)
            }
        }
        systemPowersSubscription = systemPowers.sink { [weak self] deliveredSystemPower in
            MainActor.assumeIsolated {
                self?.receive(deliveredSystemPower)
            }
        }
    }

    func stop() {
        snapshotScheduler.cancel()
        snapshotSubscription?.cancel()
        preferencesSubscription?.cancel()
        inputSourcesSubscription?.cancel()
        systemPowersSubscription?.cancel()
        snapshotSubscription = nil
        preferencesSubscription = nil
        inputSourcesSubscription = nil
        systemPowersSubscription = nil
        receivedSnapshotForStart = false
        receivedSettingsForStart = false
        receivedInputSourceForStart = false
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

    /// Input-source changes land immediately, like settings and unlike the
    /// debounced network/battery snapshots: the user just pressed a key or
    /// clicked a row, and the icon is the only feedback they get.
    ///
    /// The first delivery does not gate the start handshake: callers with no
    /// input-source publisher (the default) keep the shipped two-publisher
    /// startup, and a publisher that replays its current value still lands in
    /// the first mapped output.
    private func receive(_ inputSource: InputSourceDescriptor?) {
        latestInputSource = inputSource
        if !receivedInputSourceForStart {
            receivedInputSourceForStart = true
            if synchronizedStart {
                publishLatestOutput()
            }
            return
        }
        guard synchronizedStart else { return }

        snapshotScheduler.cancel()
        publishLatestOutput()
    }

    /// A power sample is not part of the startup handshake: the icon already
    /// has a scene, and waiting for a hardware read would delay it. A sample
    /// that lands later repaints the centre slot immediately.
    private func receive(_ systemPower: SystemPowerSample?) {
        latestSystemPower = systemPower
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
        let next = Self.output(
            snapshot: latestSnapshot,
            settings: latestSettings,
            inputSource: latestInputSource,
            systemPower: latestSystemPower,
            resolveInputs: resolveInputs,
            mapScene: mapScene
        )
        guard output != next else { return }
        output = next
    }

    private static func output(
        snapshot: StatusSnapshot,
        settings: IconPresentationSettings,
        inputSource: InputSourceDescriptor?,
        systemPower: SystemPowerSample?,
        resolveInputs: @MainActor (StatusSnapshot) -> IconPresentationInputs,
        mapScene: IconSceneMapper
    ) -> IconPresentationOutput {
        let scene = mapScene(
            resolvedInputs(
                snapshot: snapshot,
                inputSource: inputSource,
                systemPower: systemPower,
                resolveInputs: resolveInputs
            ),
            settings.configuration
        )
        let menuBarTestScene: IconSceneState?
        if settings.testsChargingEffect {
            let projected = ChargingEffectTestMode.snapshot(snapshot, enabled: true)
            menuBarTestScene = mapScene(
                resolvedInputs(
                    snapshot: projected,
                    inputSource: inputSource,
                    systemPower: systemPower,
                    resolveInputs: resolveInputs
                ),
                settings.configuration
            )
        } else {
            menuBarTestScene = nil
        }
        return IconPresentationOutput(
            scene: scene,
            menuBarTestScene: menuBarTestScene,
            menuBarSize: settings.menuBarSize
        )
    }

    /// The view model owns the input-source field so the publisher's value is
    /// the single truth, independent of what `resolveInputs` captured. It is
    /// resolved for drawing here rather than by the caller's closure, because
    /// the closure only ever sees a status snapshot: a missing icon file has to
    /// degrade to the source's short label on the live icon exactly as it does
    /// in the settings previews.
    private static func resolvedInputs(
        snapshot: StatusSnapshot,
        inputSource: InputSourceDescriptor?,
        systemPower: SystemPowerSample?,
        resolveInputs: @MainActor (StatusSnapshot) -> IconPresentationInputs
    ) -> IconPresentationInputs {
        let inputs = resolveInputs(snapshot)
        return IconPresentationInputs(
            snapshot: inputs.snapshot,
            audioIcon: inputs.audioIcon,
            inputSource: inputSource?.resolvedForDrawing(),
            systemPower: systemPower
        )
    }
}
