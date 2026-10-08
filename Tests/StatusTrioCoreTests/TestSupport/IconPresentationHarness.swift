@testable import StatusTrioCore

@MainActor
func makeTestIconPresentation(
    store: SystemStatusStore,
    settings: SettingsStore,
    snapshotScheduler: any IconPresentationScheduling = TestTaskIconPresentationScheduler()
) -> IconPresentationViewModel {
    let appearance = StatusIconAppearance(settings: settings)
    return IconPresentationViewModel(
        snapshot: store.snapshot,
        settings: IconPresentationSettings(
            configuration: settings.iconConfiguration.legacyPresentationConfiguration,
            menuBarSize: appearance.iconSize,
            testsChargingEffect: settings.testsChargingEffect,
            designerConfiguration: settings.iconConfiguration
        ),
        snapshots: store.$snapshot.eraseToAnyPublisher(),
        preferences: settings.iconPresentationPublisher,
        resolveInputs: { IconPresentationResourceResolver.inputs(snapshot: $0) },
        mapResolution: { inputs, configuration, sources in
            IconCompositionResolver.resolve(
                inputs: IconResolutionInputs(system: inputs, sources: sources),
                configuration: configuration
            )
        },
        snapshotScheduler: snapshotScheduler
    )
}

@MainActor
final class TestTaskIconPresentationScheduler: IconPresentationScheduling {
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

@MainActor
final class ManualIconPresentationScheduler: IconPresentationScheduling {
    private(set) var scheduledDelays: [Duration] = []
    private var action: (@MainActor () -> Void)?
    var hasPendingAction: Bool { action != nil }

    func schedule(after delay: Duration, action: @escaping @MainActor () -> Void) {
        scheduledDelays.append(delay)
        self.action = action
    }

    func cancel() {
        action = nil
    }

    func runScheduled() {
        let scheduledAction = action
        action = nil
        scheduledAction?()
    }
}

@MainActor
func makeIconPresentationScene(
    status: MenuBarStatus,
    battery: BatteryIconOptions = .standard,
    connection: ConnectionIconOptions = .standard,
    volume: VolumeIconOptions = .standard,
    bluetooth: BluetoothAudioIconOptions = .standard
) -> IconSceneState {
    let snapshot = StatusSnapshot(
        battery: status.battery,
        wifi: status.wifi,
        connection: status.connection,
        volume: VolumeStatus(
            scalar: status.volume.scalar,
            isMuted: status.volume.isMuted,
            deviceName: status.volume.deviceName,
            currentDevice: status.volume.currentDevice
        )
    )
    return IconPresentationMapper.scene(
        inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
        configuration: IconPresentationConfiguration(
            battery: battery,
            connection: connection,
            volume: volume,
            bluetooth: bluetooth
        )
    )
}
