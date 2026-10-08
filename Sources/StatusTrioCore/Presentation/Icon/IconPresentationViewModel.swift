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
    private let resolveInputs: @MainActor (StatusSnapshot) -> IconPresentationInputs
    private let mapScene: IconSceneMapper
    private let snapshotScheduler: any IconPresentationScheduling
    private var snapshotSubscription: AnyCancellable?
    private var preferencesSubscription: AnyCancellable?
    private var latestSnapshot: StatusSnapshot
    private var latestSettings: IconPresentationSettings
    private var receivedSnapshotForStart = false
    private var receivedSettingsForStart = false
    private var synchronizedStart = false

    init(
        snapshot: StatusSnapshot,
        settings: IconPresentationSettings,
        snapshots: AnyPublisher<StatusSnapshot, Never>,
        preferences: AnyPublisher<IconPresentationSettings, Never>,
        resolveInputs: @escaping @MainActor (StatusSnapshot) -> IconPresentationInputs,
        mapScene: @escaping IconSceneMapper = { inputs, configuration in
            IconPresentationMapper.scene(inputs: inputs, configuration: configuration)
        },
        snapshotScheduler: any IconPresentationScheduling = TaskIconPresentationScheduler()
    ) {
        self.snapshots = snapshots
        self.preferences = preferences
        self.resolveInputs = resolveInputs
        self.mapScene = mapScene
        self.snapshotScheduler = snapshotScheduler
        self.latestSnapshot = snapshot
        self.latestSettings = settings
        self.output = Self.output(
            snapshot: snapshot,
            settings: settings,
            resolveInputs: resolveInputs,
            mapScene: mapScene
        )
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
        let next = Self.output(
            snapshot: latestSnapshot,
            settings: latestSettings,
            resolveInputs: resolveInputs,
            mapScene: mapScene
        )
        guard output != next else { return }
        output = next
    }

    private static func output(
        snapshot: StatusSnapshot,
        settings: IconPresentationSettings,
        resolveInputs: @MainActor (StatusSnapshot) -> IconPresentationInputs,
        mapScene: IconSceneMapper
    ) -> IconPresentationOutput {
        let scene = mapScene(resolveInputs(snapshot), settings.configuration)
        let menuBarTestScene: IconSceneState?
        if settings.testsChargingEffect {
            let projected = ChargingEffectTestMode.snapshot(snapshot, enabled: true)
            menuBarTestScene = mapScene(resolveInputs(projected), settings.configuration)
        } else {
            menuBarTestScene = nil
        }
        return IconPresentationOutput(
            scene: scene,
            menuBarTestScene: menuBarTestScene,
            menuBarSize: settings.menuBarSize
        )
    }
}
