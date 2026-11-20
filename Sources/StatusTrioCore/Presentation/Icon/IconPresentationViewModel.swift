import Combine
import Foundation

typealias IconSceneMapper = @MainActor (
    IconPresentationInputs,
    IconPresentationConfiguration,
    IconConfigurationV1,
    IconSlotBindingsV1?
) -> IconSceneMapping

/// Scene plus the source demand that produced it. The demand travels with the
/// scene so the host never re-derives it from pixels or from a possibly stale
/// persisted configuration.
struct IconSceneMapping: Equatable, Sendable {
    var scene: IconSceneState
    var demand: IconPresentationDemand = .none

    init(scene: IconSceneState, demand: IconPresentationDemand = .none) {
        self.scene = scene
        self.demand = demand
    }
}

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
    /// The V1 icon configuration this settings snapshot was built from.
    ///
    /// The merged runtime renders through `IconCompositionResolver`, which needs
    /// the V1 schema. Carrying it in the published settings (rather than reading
    /// the store from inside `mapScene`) keeps the scene and the settings that
    /// produced it in the same snapshot, so a settings change is rendered once
    /// instead of showing a stale scene first.
    var iconConfiguration: IconConfigurationV1 = .classic
    /// Runtime-only icon options carried in the same snapshot as the appearance
    /// they were derived from. Using this (instead of reading the store inside
    /// `resolveInputs`) avoids the `@Published` willSet race that made a live
    /// change publish the *previous* value one step late.
    var runtimeOptions: IconPresentationRuntimeOptions? = nil
    /// The versioned plugin bindings the scene renders from. `nil` keeps older
    /// call sites and previews on the one-time migration from `iconConfiguration`.
    var slotBindings: IconSlotBindingsV1? = nil
    /// Delivered with the settings snapshot so colour/cap edits are read from the
    /// value that produced this publication, not from the live store during
    /// `@Published` willSet (which lags one edit).
    var hardwareMetricColors: [HardwareMonitorMetric: IconRGBA] = [:]
    var hardwareDownloadCapMbps: Double = 1000
    var hardwareUploadCapMbps: Double = 100
}

struct IconPresentationOutput: Equatable, Sendable {
    let scene: IconSceneState
    var menuBarTestScene: IconSceneState? = nil
    let menuBarSize: Double
    var demand: IconPresentationDemand = .none

    /// Demand is published separately (even when the pixels are unchanged), so
    /// equality for repaint deduplication deliberately ignores it.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.scene == rhs.scene
            && lhs.menuBarTestScene == rhs.menuBarTestScene
            && lhs.menuBarSize == rhs.menuBarSize
    }
}

@MainActor
final class IconPresentationViewModel: ObservableObject {
    static let snapshotDebounceInterval: Duration = .milliseconds(500)

    @Published private(set) var output: IconPresentationOutput
    /// Live-source demand from the most recent resolution. Published even when
    /// the scene is pixel-identical, because a different binding can need a
    /// different watch or metric sample.
    @Published private(set) var demand: IconPresentationDemand

    private let snapshots: AnyPublisher<StatusSnapshot, Never>
    private let preferences: AnyPublisher<IconPresentationSettings, Never>
    private let inputSources: AnyPublisher<InputSourceDescriptor?, Never>
    private let systemPowers: AnyPublisher<SystemPowerSample?, Never>
    private let highPowerModes: AnyPublisher<Bool, Never>
    /// Hardware-metric ticks repaint the icon only while a hardware ring is on
    /// screen; `resolveInputs` reads the live snapshot from the store.
    private let hardwareMetrics: AnyPublisher<HardwareMetricsSnapshot, Never>
    private let resolveInputs: @MainActor (StatusSnapshot) -> IconPresentationInputs
    private let mapScene: IconSceneMapper
    private let snapshotScheduler: any IconPresentationScheduling
    private var snapshotSubscription: AnyCancellable?
    private var preferencesSubscription: AnyCancellable?
    private var inputSourcesSubscription: AnyCancellable?
    private var systemPowersSubscription: AnyCancellable?
    private var highPowerModesSubscription: AnyCancellable?
    private var hardwareMetricsSubscription: AnyCancellable?
    private var latestSnapshot: StatusSnapshot
    private var latestSettings: IconPresentationSettings
    private var latestInputSource: InputSourceDescriptor?
    private var latestSystemPower: SystemPowerSample?
    private var latestHighPowerMode = false
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
        highPowerModes: AnyPublisher<Bool, Never> = Empty<Bool, Never>().eraseToAnyPublisher(),
        hardwareMetrics: AnyPublisher<HardwareMetricsSnapshot, Never> = Empty<HardwareMetricsSnapshot, Never>().eraseToAnyPublisher(),
        resolveInputs: @escaping @MainActor (StatusSnapshot) -> IconPresentationInputs,
        mapScene: @escaping IconSceneMapper = { inputs, configuration, _, _ in
            IconSceneMapping(
                scene: IconPresentationMapper.scene(inputs: inputs, configuration: configuration))
        },
        snapshotScheduler: any IconPresentationScheduling = TaskIconPresentationScheduler()
    ) {
        self.snapshots = snapshots
        self.preferences = preferences
        self.inputSources = inputSources
        self.systemPowers = systemPowers
        self.highPowerModes = highPowerModes
        self.hardwareMetrics = hardwareMetrics
        self.resolveInputs = resolveInputs
        self.mapScene = mapScene
        self.snapshotScheduler = snapshotScheduler
        self.latestSnapshot = snapshot
        self.latestSettings = settings
        let initialOutput = Self.output(
            snapshot: snapshot,
            settings: settings,
            inputSource: nil,
            systemPower: nil,
            isHighPowerMode: false,
            resolveInputs: resolveInputs,
            mapScene: mapScene
        )
        self.output = initialOutput
        self.demand = initialOutput.demand
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
        highPowerModesSubscription = highPowerModes.sink { [weak self] isHighPowerMode in
            MainActor.assumeIsolated {
                self?.receive(highPowerMode: isHighPowerMode)
            }
        }
        hardwareMetricsSubscription = hardwareMetrics.sink { [weak self] snapshot in
            MainActor.assumeIsolated {
                self?.receive(hardwareMetrics: snapshot)
            }
        }
    }

    /// Re-resolves the current snapshot without waiting for a settings or
    /// snapshot publisher. Used when an external live package updates its
    /// reading or the plugin registry changes.
    func refresh() {
        guard synchronizedStart else { return }
        snapshotScheduler.cancel()
        publishLatestOutput()
    }

    func stop() {
        snapshotScheduler.cancel()
        snapshotSubscription?.cancel()
        preferencesSubscription?.cancel()
        inputSourcesSubscription?.cancel()
        systemPowersSubscription?.cancel()
        highPowerModesSubscription?.cancel()
        hardwareMetricsSubscription?.cancel()
        snapshotSubscription = nil
        preferencesSubscription = nil
        inputSourcesSubscription = nil
        systemPowersSubscription = nil
        highPowerModesSubscription = nil
        hardwareMetricsSubscription = nil
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

    /// High Power Mode changes repaint immediately: the user just moved the
    /// Power Mode control and the icon colour is the feedback.
    private func receive(highPowerMode: Bool) {
        latestHighPowerMode = highPowerMode
        guard synchronizedStart else { return }
        snapshotScheduler.cancel()
        publishLatestOutput()
    }

    /// A hardware-metric tick only affects the icon while a hardware ring is on
    /// screen; when it is not, the resolved scene is unchanged and `output`
    /// equality short-circuits the publish, so this is cheap for battery/AirPods
    /// users. Sampling itself is demand-driven elsewhere.
    private func receive(hardwareMetrics: HardwareMetricsSnapshot) {
        guard synchronizedStart else { return }
        // Only re-resolve when the hardware ring is actually selected (primary or
        // fallback). Panel/card hardware ticks must not re-parse an icon that is
        // drawing the Mac battery, AirPods or another source.
        let isHardwareRing: Bool
        if let bindings = latestSettings.slotBindings {
            let selection = bindings.selection(for: .outerRing)
            isHardwareRing = selection.primary?.pluginID == "builtin.hardware-monitor"
                || selection.fallback?.pluginID == "builtin.hardware-monitor"
        } else {
            let composition = latestSettings.iconConfiguration.composition.outerRing
            isHardwareRing = composition.primary == .hardwareMonitor
                || composition.fallback == .hardwareMonitor
        }
        guard isHardwareRing else { return }
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
            isHighPowerMode: latestHighPowerMode,
            resolveInputs: resolveInputs,
            mapScene: mapScene
        )
        if next.demand != demand { demand = next.demand }
        guard output != next else { return }
        output = next
    }

    private static func output(
        snapshot: StatusSnapshot,
        settings: IconPresentationSettings,
        inputSource: InputSourceDescriptor?,
        systemPower: SystemPowerSample?,
        isHighPowerMode: Bool,
        resolveInputs: @MainActor (StatusSnapshot) -> IconPresentationInputs,
        mapScene: IconSceneMapper
    ) -> IconPresentationOutput {
        let mapping = mapScene(
            resolvedInputs(
                snapshot: snapshot,
                inputSource: inputSource,
                systemPower: systemPower,
                isHighPowerMode: isHighPowerMode,
                settingsRuntimeOptions: settings.runtimeOptions,
                hardwareMetricColors: settings.hardwareMetricColors,
                hardwareDownloadCapMbps: settings.hardwareDownloadCapMbps,
                hardwareUploadCapMbps: settings.hardwareUploadCapMbps,
                resolveInputs: resolveInputs
            ),
            settings.configuration,
            settings.iconConfiguration,
            settings.slotBindings
        )
        let scene = mapping.scene
        let menuBarTestScene: IconSceneState?
        if settings.testsChargingEffect {
            let projected = ChargingEffectTestMode.snapshot(snapshot, enabled: true)
            menuBarTestScene = mapScene(
                resolvedInputs(
                    snapshot: projected,
                    inputSource: inputSource,
                    systemPower: systemPower,
                    isHighPowerMode: isHighPowerMode,
                    settingsRuntimeOptions: settings.runtimeOptions,
                    hardwareMetricColors: settings.hardwareMetricColors,
                    hardwareDownloadCapMbps: settings.hardwareDownloadCapMbps,
                    hardwareUploadCapMbps: settings.hardwareUploadCapMbps,
                    resolveInputs: resolveInputs
                ),
                settings.configuration,
                settings.iconConfiguration,
                settings.slotBindings
            ).scene
        } else {
            menuBarTestScene = nil
        }
        return IconPresentationOutput(
            scene: scene,
            menuBarTestScene: menuBarTestScene,
            menuBarSize: settings.menuBarSize,
            demand: mapping.demand
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
        isHighPowerMode: Bool,
        settingsRuntimeOptions: IconPresentationRuntimeOptions?,
        hardwareMetricColors: [HardwareMonitorMetric: IconRGBA],
        hardwareDownloadCapMbps: Double,
        hardwareUploadCapMbps: Double,
        resolveInputs: @MainActor (StatusSnapshot) -> IconPresentationInputs
    ) -> IconPresentationInputs {
        var inputs = resolveInputs(snapshot)
        // Carry every field the resolver needs. Colours, caps and runtime options
        // come from the published settings snapshot: reading them live here would
        // read the pre-change value during `@Published`'s willSet emission and lag
        // one edit behind.
        inputs.sources.hardwareMetricColors = hardwareMetricColors
        inputs.sources.hardwareSpeedCapsMbps = [
            .downloadSpeed: hardwareDownloadCapMbps,
            .uploadSpeed: hardwareUploadCapMbps
        ]
        return IconPresentationInputs(
            snapshot: inputs.snapshot,
            audioIcon: inputs.audioIcon,
            inputSource: inputSource?.resolvedForDrawing(),
            runtimeOptions: settingsRuntimeOptions ?? inputs.runtimeOptions,
            systemPower: systemPower,
            isHighPowerMode: isHighPowerMode,
            sources: inputs.sources,
            bottomIndicatorSource: settingsRuntimeOptions?.bottomIndicatorSource
                ?? inputs.bottomIndicatorSource
        )
    }
}
